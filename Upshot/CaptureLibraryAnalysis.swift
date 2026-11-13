
import AppKit

nonisolated enum CaptureCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case code, design, website, document, chat, email, data, error, receipt, social, media, settings, other

    var id: Self { self }

    var title: String {
        switch self {
        case .code: "Code"
        case .design: "Design"
        case .website: "Websites"
        case .document: "Documents"
        case .chat: "Conversations"
        case .email: "Email"
        case .data: "Charts & Data"
        case .error: "Errors"
        case .receipt: "Receipts & Orders"
        case .social: "Social"
        case .media: "Photos & Video"
        case .settings: "Settings"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .code: "apple.terminal.fill"
        case .design: "paintpalette"
        case .website: "globe"
        case .document: "doc.text"
        case .chat: "bubble.left.and.bubble.right"
        case .email: "envelope"
        case .data: "chart.bar"
        case .error: "exclamationmark.triangle"
        case .receipt: "receipt"
        case .social: "person.2"
        case .media: "photo.on.rectangle.angled"
        case .settings: "gearshape"
        case .other: "photo.stack"
        }
    }

    var guidance: String {
        switch self {
        case .code: "source code, terminals, IDEs, diffs, logs, developer tools"
        case .design: "UI designs, mockups, design tools, icons, typography, layouts"
        case .website: "web pages, landing pages, articles in a browser, search results"
        case .document: "documents, notes, PDFs, wikis, slides, long-form text"
        case .chat: "chat and messaging threads, comments, DMs"
        case .email: "email messages and inboxes"
        case .data: "spreadsheets, tables, charts, dashboards, analytics"
        case .error: "error messages, crash reports, warnings, failed builds, alerts"
        case .receipt: "receipts, invoices, orders, payments, bookings, tickets"
        case .social: "social media posts, profiles and feeds"
        case .media: "photos, video frames, artwork, maps, games"
        case .settings: "settings, preferences, system dialogs, configuration screens"
        case .other: "anything that fits none of the others"
        }
    }
}

nonisolated struct CaptureTextLine: Codable, Sendable, Equatable {
    var text: String
    var box: CGRect?
}

nonisolated struct CaptureTextLines: Codable, Sendable, Equatable, RandomAccessCollection {
    private(set) var text = ""
    private var ends: [UInt32] = []
    private var boxes: [Float] = []

    init() {}

    init(_ lines: [CaptureTextLine]) {
        text = lines.map(\.text).joined(separator: "\n")
        ends.reserveCapacity(lines.count)
        boxes.reserveCapacity(lines.count * 4)
        var offset = 0
        for line in lines {
            offset += line.text.utf8.count
            ends.append(UInt32(offset))
            let box = line.box
            boxes += box.map { [Float($0.minX), Float($0.minY), Float($0.width), Float($0.height)] } ?? [.nan, .nan, .nan, .nan]
            offset += 1
        }
    }

    init(from decoder: Decoder) throws {
        self.init(try [CaptureTextLine](from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        try Array(self).encode(to: encoder)
    }

    var startIndex: Int { 0 }
    var endIndex: Int { ends.count }

    subscript(position: Int) -> CaptureTextLine {
        let utf8 = text.utf8
        let start = position == 0 ? 0 : Int(ends[position - 1]) + 1
        let lower = utf8.index(utf8.startIndex, offsetBy: start)
        let upper = utf8.index(lower, offsetBy: Int(ends[position]) - start)
        let i = position * 4
        let box = boxes[i].isNaN ? nil : CGRect(x: CGFloat(boxes[i]), y: CGFloat(boxes[i + 1]),
                                                width: CGFloat(boxes[i + 2]), height: CGFloat(boxes[i + 3]))
        return CaptureTextLine(text: String(decoding: utf8[lower..<upper], as: UTF8.self), box: box)
    }
}

nonisolated struct CaptureAnalysis: Codable, Sendable, Equatable {
    enum Classifier: String, Codable, Sendable {
        case model
        case rules
    }

    static let currentVersion = 2

    var id: String
    var version = Self.currentVersion
    var fingerprint: String
    var lines = CaptureTextLines()
    var transcript: String?
    var category: CaptureCategory?
    var title: String?
    var keywords: [String] = []
    var classifier: Classifier?
    var modelDeclined = false
    var hasFeaturePrint = false

    var text: String { lines.text }
}

nonisolated enum CaptureCategoryRules {
    static func category(source: CaptureSource?, text: String, isVideo: Bool) -> CaptureCategory {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if hits(errorWords, in: folded) >= 2 { return .error }
        if hits(receiptWords, in: folded) >= 2, folded.range(of: #"[$€£¥₹]\s?\d"#, options: .regularExpression) != nil {
            return .receipt
        }
        if let category = appCategory(source) { return category }
        if hits(codeWords, in: folded) >= 3 { return .code }
        if isVideo { return .media }
        return folded.count > 400 ? .document : .other
    }

    private static func hits(_ words: [String], in text: String) -> Int {
        words.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
    }

    private static let errorWords = ["error", "exception", "failed", "fatal", "traceback", "stack trace", "crash", "warning:", "undefined"]
    private static let receiptWords = ["total", "subtotal", "invoice", "receipt", "order", "paid", "payment", "tax", "amount due"]
    private static let codeWords = ["func ", "return ", "import ", "const ", "let ", "class ", "def ", "=> ", "();", "{", "}"]

    private static func appCategory(_ source: CaptureSource?) -> CaptureCategory? {
        guard let source else { return nil }
        let id = source.bundleIdentifier?.lowercased() ?? ""
        let name = source.appName.lowercased()
        func matches(_ needles: [String]) -> Bool { needles.contains { id.contains($0) || name.contains($0) } }
        if matches(["xcode", "terminal", "iterm", "vscode", "visualstudio", "cursor", "ghostty", "zed", "jetbrains", "warp", "sublime", "nova", "tower", "fork", "github"]) { return .code }
        if matches(["figma", "sketch", "pixelmator", "photoshop", "illustrator", "affinity", "framer", "spline", "rive"]) { return .design }
        if matches(["slack", "messages", "ichat", "discord", "whatsapp", "telegram", "signal", "teams", "messenger"]) { return .chat }
        if matches(["mail", "outlook", "spark", "mimestream", "superhuman", "airmail"]) { return .email }
        if matches(["numbers", "excel", "tableplus", "sequel", "datagrip"]) { return .data }
        if matches(["pages", "word", "notes", "notion", "obsidian", "bear", "craft", "preview", "acrobat", "keynote", "powerpoint", "textedit"]) { return .document }
        if matches(["safari", "chrome", "firefox", "arc", "edge", "brave", "orion", "opera", "dia"]) { return .website }
        if matches(["photos", "quicktime", "music", "tv", "maps", "iina", "vlc"]) { return .media }
        if matches(["systempreferences", "systemsettings", "system settings"]) { return .settings }
        if matches(["twitter", "tweetbot", "ivory", "mastodon", "threads", "bluesky"]) { return .social }
        return appStoreCategory(id)
    }

    private static func appStoreCategory(_ bundleIdentifier: String) -> CaptureCategory? {
        guard !bundleIdentifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let declared = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        else { return nil }
        switch declared.replacingOccurrences(of: "public.app-category.", with: "") {
        case "developer-tools": return .code
        case "graphics-design": return .design
        case "photography", "video", "music", "entertainment", "games": return .media
        case "social-networking": return .social
        case "productivity", "business", "reference", "education": return .document
        case "finance": return .data
        default: return nil
        }
    }
}
