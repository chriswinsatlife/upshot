import CryptoKit
import Foundation

nonisolated final class GrowingCloudUploadSource: @unchecked Sendable {
    struct Snapshot: Sendable {
        let url: URL?
        let isFinal: Bool
    }

    private let lock = NSLock()
    private var url: URL?
    private var isFinal = false
    private var failure: (any Error)?

    func opened(_ url: URL) {
        lock.withLock { self.url = url }
    }

    func finished(_ url: URL) {
        lock.withLock {
            self.url = url
            isFinal = true
        }
    }

    func failed(_ error: any Error) {
        lock.withLock { failure = error }
    }

    func snapshot() throws -> Snapshot {
        try lock.withLock {
            if let failure { throw failure }
            return Snapshot(url: url, isFinal: isFinal)
        }
    }
}

nonisolated enum MultipartCloudUpload {
    private static let partSize = 16 * 1024 * 1024
    private static let maximumSize: UInt64 = 100_000_000_000

    private struct Session: Decodable {
        let id: String
        let key: String
        let uploadId: String
    }

    private struct Part: Codable, Sendable {
        let partNumber: Int
        let etag: String
    }

    private struct UploadedPart: Sendable {
        let part: Part
        let digest: Data
    }

    private struct Completion: Encodable {
        let key: String
        let uploadId: String
        let parts: [Part]
    }

    private enum UploadError: LocalizedError {
        case workerNeedsUpdate, rejected(Int)

        var errorDescription: String? {
            switch self {
            case .workerNeedsUpdate:
                "Update the Upshot Cloud Worker to upload large recordings."
            case .rejected(let status):
                "Cloud upload failed (HTTP \(status))."
            }
        }
    }

    static func upload(
        fileURL: URL,
        request template: URLRequest,
        progress: (@Sendable (Double) -> Void)?,
        growingSource: GrowingCloudUploadSource? = nil
    ) async throws -> (Data, URLResponse) {
        guard let uploadURL = template.url else { throw URLError(.badURL) }
        var start = template
        start.url = uploadURL.appendingPathComponent("multipart")
        start.httpMethod = "POST"
        let session: Session
        do {
            session = try JSONDecoder().decode(Session.self, from: await send(start).0)
        } catch UploadError.rejected(let status) where status == 404 || status == 405 {
            throw UploadError.workerNeedsUpdate
        }
        var request = template
        request.url = start.url!.appendingPathComponent(session.id)
        var query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        query.queryItems = [
            URLQueryItem(name: "key", value: session.key),
            URLQueryItem(name: "uploadId", value: session.uploadId),
        ]
        let partRequest = request
        let partQuery = query
        var uploaded: [Int: UploadedPart] = [:]
        var nextPart = 1
        var completing = false
        do {
            var finalURL = fileURL
            var finalSize: UInt64 = 0
            while true {
                try Task.checkCancellation()
                let state = try growingSource?.snapshot()
                    ?? GrowingCloudUploadSource.Snapshot(url: fileURL, isFinal: true)
                guard let url = state.url else {
                    try await Task.sleep(for: .milliseconds(250))
                    continue
                }
                let size = try fileSize(at: url)
                let limit = growingSource == nil ? UInt64(partSize) * 10_000 : maximumSize
                guard size <= limit else { throw URLError(.dataLengthExceedsMaximum) }
                let availableParts = state.isFinal
                    ? Int((size + UInt64(partSize) - 1) / UInt64(partSize))
                    : Int(size / UInt64(partSize))
                if nextPart <= availableParts {
                    let upper = min(nextPart + 2, availableParts)
                    let batch = Array(nextPart...upper)
                    let results = try await withThrowingTaskGroup(of: UploadedPart.self) { group in
                        for number in batch {
                            group.addTask {
                                let offset = UInt64(number - 1) * UInt64(partSize)
                                let count = Int(min(UInt64(partSize), size - offset))
                                return try await uploadPart(
                                    number: number, data: read(url, offset: offset, count: count),
                                    request: partRequest, query: partQuery
                                )
                            }
                        }
                        var results: [UploadedPart] = []
                        for try await result in group { results.append(result) }
                        return results
                    }
                    for result in results { uploaded[result.part.partNumber] = result }
                    nextPart = upper + 1
                    if state.isFinal { progress?(min(0.98, Double(upper * partSize) / Double(max(size, 1)))) }
                    continue
                }
                if state.isFinal {
                    guard size > 0 else { throw URLError(.zeroByteResource) }
                    finalURL = url
                    finalSize = size
                    break
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            let finalPartCount = Int((finalSize + UInt64(partSize) - 1) / UInt64(partSize))
            if growingSource != nil {
                for number in 1...finalPartCount {
                    try Task.checkCancellation()
                    let offset = UInt64(number - 1) * UInt64(partSize)
                    let data = try read(finalURL, offset: offset, count: Int(min(UInt64(partSize), finalSize - offset)))
                    if uploaded[number]?.digest != Data(SHA256.hash(data: data)) {
                        uploaded[number] = try await uploadPart(number: number, data: data, request: request, query: query)
                        AppLog.event("recording", "cloud_upload_part_replaced", fields: ["part": String(number)])
                    }
                }
            }
            let parts = (1...finalPartCount).compactMap { uploaded[$0]?.part }
            guard parts.count == finalPartCount else { throw URLError(.badServerResponse) }
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = try JSONEncoder().encode(Completion(key: session.key, uploadId: session.uploadId, parts: parts))
            try Task.checkCancellation()
            completing = true
            return try await send(request, body: body)
        } catch {
            if !completing {
                var abort = request
                abort.url = query.url
                abort.httpMethod = "DELETE"
                abort.timeoutInterval = 10
                let abortRequest = abort
                await Task.detached {
                    do { _ = try await send(abortRequest) }
                    catch { AppLog.event("recording", "cloud_upload_abort_failed", fields: ["error": AppLog.error(error)]) }
                }.value
            }
            AppLog.event("recording", "cloud_multipart_upload_failed", fields: ["error": AppLog.error(error), "completing": String(completing)])
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private static func fileSize(at url: URL) throws -> UInt64 {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try file.seekToEnd()
    }

    private static func read(_ url: URL, offset: UInt64, count: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: offset)
        guard let data = try file.read(upToCount: count), data.count == count else {
            throw CocoaError(.fileReadUnknown)
        }
        return data
    }

    private static func uploadPart(
        number: Int, data: Data, request template: URLRequest, query: URLComponents
    ) async throws -> UploadedPart {
        var query = query
        query.queryItems!.append(URLQueryItem(name: "partNumber", value: String(number)))
        var request = template
        request.url = query.url
        request.httpMethod = "PUT"
        for attempt in 1...3 {
            do {
                let part = try JSONDecoder().decode(Part.self, from: await send(request, body: data).0)
                guard part.partNumber == number, !part.etag.isEmpty else { throw URLError(.badServerResponse) }
                return UploadedPart(part: part, digest: Data(SHA256.hash(data: data)))
            } catch {
                try Task.checkCancellation()
                let retryable: Bool
                if case UploadError.rejected(let status) = error {
                    retryable = [408, 425, 429].contains(status) || (500..<600).contains(status)
                } else if let network = error as? URLError {
                    retryable = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(network.code)
                } else {
                    retryable = false
                }
                guard attempt < 3, retryable else { throw error }
                AppLog.event("recording", "cloud_upload_part_retry", fields: ["part": String(number), "attempt": String(attempt), "error": AppLog.error(error)])
                try await Task.sleep(for: .milliseconds(attempt == 1 ? 300 : 900))
            }
        }
        throw URLError(.badServerResponse)
    }

    private static func send(_ request: URLRequest, body: Data? = nil) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let result: (Data, URLResponse)
        if let body {
            result = try await URLSession.shared.upload(for: request, from: body)
        } else {
            result = try await URLSession.shared.data(for: request)
        }
        guard let response = result.1 as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else { throw UploadError.rejected(response.statusCode) }
        return result
    }
}
