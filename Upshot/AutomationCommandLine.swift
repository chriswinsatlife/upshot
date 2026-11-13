import Darwin
import Foundation

nonisolated struct AutomationCommand {
    let method: String
    let parameters: JSONValue
    let socketURL: URL
    let timeout: TimeInterval
    let printsJSON: Bool

    init(arguments: [String]) throws {
        var values = arguments
        var positional: [String] = []
        var parameters: [String: JSONValue] = [:]
        var socketURL = AgentSocket.url
        var timeout: TimeInterval = 300
        var printsJSON = false
        while !values.isEmpty {
            let argument = values.removeFirst()
            switch argument {
            case "--dev": socketURL = AgentSocket.url.deletingLastPathComponent().appendingPathComponent("agent-dev.sock")
            case "--json": printsJSON = true
            case "--output", "--path", "--delay", "--timeout", "--socket":
                guard !values.isEmpty else { throw AutomationError.message("Missing value for \(argument).") }
                let value = values.removeFirst()
                switch argument {
                case "--timeout":
                    guard let seconds = Double(value), seconds.isFinite, seconds > 0 else { throw AutomationError.message("Timeout must be a positive number of seconds.") }
                    timeout = seconds
                case "--socket": socketURL = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
                default:
                    let key = String(argument.dropFirst(2))
                    guard parameters[key] == nil else { throw AutomationError.message("Duplicate option: \(argument)") }
                    parameters[key] = .string(key == "path" || key == "output" ? URL(fileURLWithPath: (value as NSString).expandingTildeInPath).path : value)
                }
            default:
                guard !argument.hasPrefix("-") else { throw AutomationError.message("Unknown option: \(argument)") }
                positional.append(argument)
            }
        }
        if positional == ["actions"] {
            guard parameters.isEmpty else { throw AutomationError.message("The actions command takes no action parameters.") }
            method = "upshot/actions"
            self.parameters = [:]
        } else {
            guard positional.count == 2 else { throw AutomationError.message("Expected a command and action. Run upshot --help for usage.") }
            method = "upshot/perform"
            self.parameters = ["route": .string(positional.joined(separator: "/")), "parameters": .object(parameters)]
        }
        self.socketURL = socketURL
        self.timeout = timeout
        self.printsJSON = printsJSON
    }
}

nonisolated enum AutomationCommandLine {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--cli") || URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "upshot"
    }

    static let usage = """
    Usage: upshot <command> <action> [options]
           upshot actions [--json]

    Capture:   capture fullscreen|window|area|text|area-copy|area-save|area-upload|self-timer|previous-area
    Recording: recording picker|start|stop|toggle|pause|resume|restart|discard
    Editor:    editor open|recording [--path FILE]
    Library:   library open|screenshots|recordings|restore-last|folder
    Settings:  settings general|screenshots|video|overlay|mcp|cloud|about

    --output FILE    Write a capture to a new PNG file; text captures write UTF-8.
    --delay SECONDS  Set the self-timer delay, default 5.
    --path FILE      Open an image, recording project, or video in an editor.
    --dev            Connect to Upshot Dev.
    --socket FILE    Connect to a specific Unix socket.
    --timeout SEC    Response timeout, default 300 seconds.
    --json           Print the structured result.
    --help           Print this help without connecting to the app.

    Upshot must already be running with Allow AI agents enabled in Settings → MCP.
    """

    static func run() -> Never {
        let arguments = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--cli" }
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] {
            print(usage)
            exit(0)
        }
        do {
            let command = try AutomationCommand(arguments: arguments)
            let result = try request(command)
            if command.printsJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                print(String(decoding: try encoder.encode(result), as: UTF8.self))
            } else if let path = result["path"]?.stringValue {
                print(path)
            } else if let text = result["text"]?.stringValue {
                print(text)
            } else if let actions = result["actions"]?.arrayValue {
                for action in actions {
                    print("\(action["route"]?.stringValue ?? "")\t\(action["title"]?.stringValue ?? "")")
                }
            } else {
                print(result["status"]?.stringValue ?? "completed")
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("upshot: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func request(_ command: AutomationCommand) throws -> JSONValue {
        guard let descriptor = AgentSocket.connect(to: command.socketURL) else {
            throw AutomationError.message("Cannot connect to Upshot. Open the app and enable Allow AI agents in Settings → MCP. Use --dev for Upshot Dev.")
        }
        defer { close(descriptor) }
        let message: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": .string(command.method), "params": command.parameters]
        guard AgentSocket.writeAll(try message.encodedLine(), to: descriptor) else { throw AutomationError.message("The request could not be sent.") }
        let deadline = Date().addingTimeInterval(command.timeout)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw AutomationError.message("The request timed out. The app may still be completing the action; check before retrying.") }
            var descriptorState = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptorState, 1, Int32(min(remaining * 1000, Double(Int32.max))))
            if ready < 0, errno == EINTR { continue }
            guard ready >= 0 else { throw AutomationError.message("The socket could not be read.") }
            guard ready > 0 else { continue }
            let count = read(descriptor, &chunk, chunk.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw AutomationError.message("Upshot disconnected before returning a result.") }
            buffer.append(contentsOf: chunk[..<count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                let response = try JSONValue.decoder.decode(JSONValue.self, from: line)
                guard response["id"] == .number(1) else { continue }
                if let error = response["error"] { throw AutomationError.message(error["message"]?.stringValue ?? "Upshot rejected the action.") }
                guard let result = response["result"] else { throw AutomationError.message("Upshot returned an invalid response.") }
                return result
            }
        }
    }
}
