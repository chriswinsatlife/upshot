import Accelerate
import AppKit
import CryptoKit
import Observation
import Vision

@MainActor
@Observable
final class CaptureLibraryIndex {
    static let shared = CaptureLibraryIndex()

    private(set) var analyses: [String: CaptureAnalysis] = [:]

    private(set) var revision = 0

    private(set) var readingCount = 0
    private(set) var sortingCount = 0

    private(set) var unsortedExistingCount = 0

    var pendingCount: Int { readingCount + sortingCount }

    @ObservationIgnored private let store = CaptureLibraryIndexStore(
        directory: ScreenshotHistoryStore.applicationSupportDirectory.appendingPathComponent("Library Index", isDirectory: true)
    )

    @ObservationIgnored private(set) var isLoaded = false
    @ObservationIgnored private var latestItems: [CaptureLibraryItem]?
    @ObservationIgnored private var readQueue: [CaptureLibraryItem] = []
    @ObservationIgnored private var sortQueue: [CaptureLibraryItem] = []

    @ObservationIgnored private var inFlight: CaptureLibraryItem?

    @ObservationIgnored private var unreadable: Set<String> = []
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var unpublished: [String: CaptureAnalysis] = [:]
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        observeHistory()
        load()
    }

    func libraryDidOpen() {
        load()
    }

    func libraryDidClose() {
        Task { await store.forgetFeaturePrints() }
    }

    private func load() {
        guard started, !isLoaded, loadTask == nil else { return }
        loadTask = Task {
            let loaded = await store.loadAll()
            loadTask = nil
            analyses = loaded
            isLoaded = true
            revision &+= 1
            CaptureLibraryModel.shared.indexDidChange(changed: Set(loaded.keys))
            if let latestItems { sync(latestItems) } else { CaptureLibraryModel.shared.refresh() }
        }
    }

    func settingsDidChange() {
        if let latestItems { sync(latestItems) }
    }

    func sortExistingCaptures() {
        UpshotStorage.defaults.set(true, forKey: UpshotPreferences.librarySortExistingKey)
        settingsDidChange()
    }

    func sync(_ items: [CaptureLibraryItem]) {
        latestItems = items
        guard isLoaded else { load(); return }
        let live = Set(items.lazy.map(\.id))

        if !items.isEmpty {
            let gone = analyses.keys.filter { !live.contains($0) }
            if !gone.isEmpty {
                for id in gone { analyses[id] = nil }
                revision &+= 1
                Task { await store.remove(ids: gone) }
            }
        }
        guard UpshotPreferences.libraryAnalyzeCaptures else {
            readQueue = []
            sortQueue = []
            unsortedExistingCount = 0
            updateCounts()
            return
        }
        let modelAvailable = CaptureLibraryAnalyzer.isModelAvailable
        let sortExisting = UpshotPreferences.librarySortExisting
        let autoSortSince = UpshotPreferences.libraryAutoSortSince
        var reads: [CaptureLibraryItem] = []
        var sorts: [CaptureLibraryItem] = []
        var unsortedExisting = 0
        for item in items where item != inFlight && !unreadable.contains(item.thumbnailKey) {
            let analysis = analyses[item.id] ?? unpublished[item.id]
            guard let analysis,
                  analysis.version == CaptureAnalysis.currentVersion,
                  analysis.fingerprint == item.thumbnailKey else {
                reads.append(item)
                continue
            }
            guard modelAvailable, analysis.classifier != .model, !analysis.modelDeclined else { continue }
            if sortExisting || item.createdAt >= autoSortSince {
                sorts.append(item)
            } else {
                unsortedExisting += 1
            }
        }
        readQueue = reads.sorted { $0.createdAt > $1.createdAt }
        sortQueue = sorts.sorted { $0.createdAt > $1.createdAt }
        unsortedExistingCount = unsortedExisting
        updateCounts()
        if pendingCount > 0, runner == nil { runner = Task { await drain() } }
    }

    func similar(to id: String, among candidates: [String], limit: Int) async -> [String] {
        guard analyses[id]?.hasFeaturePrint == true else { return [] }
        let withPrints = candidates.filter { $0 != id && analyses[$0]?.hasFeaturePrint == true }
        return await store.nearest(to: id, among: withPrints, limit: limit)
    }

    private func drain() async {
        defer { runner = nil }
        while UpshotPreferences.libraryAnalyzeCaptures {
            if shouldPause {
                try? await Task.sleep(for: .seconds(10))
                continue
            }

            let isReading = !readQueue.isEmpty
            guard let item = isReading ? readQueue.first : sortQueue.first else { break }
            if isReading { readQueue.removeFirst() } else { sortQueue.removeFirst() }
            inFlight = item
            defer { inFlight = nil }
            let previous = analyses[item.id] ?? unpublished[item.id]
            let work = Task.detached(priority: .background) { () -> CaptureLibraryAnalyzer.Result? in
                if !isReading, let previous {
                    return .init(analysis: await CaptureLibraryAnalyzer.sort(previous, item: item), featurePrint: nil)
                }
                return await CaptureLibraryAnalyzer.read(item, previous: previous)
            }
            if let result = await work.value {
                await store.save(result.analysis, featurePrint: result.featurePrint)
                unpublished[item.id] = result.analysis
                schedulePublish()

                if isReading, result.analysis.classifier != .model, CaptureLibraryAnalyzer.isModelAvailable {
                    if isDueForSorting(item) { sortQueue.append(item) } else { unsortedExistingCount += 1 }
                }
            } else {
                unreadable.insert(item.thumbnailKey)
            }
            updateCounts()
        }
        publish()
    }

    private func isDueForSorting(_ item: CaptureLibraryItem) -> Bool {
        UpshotPreferences.librarySortExisting || item.createdAt >= UpshotPreferences.libraryAutoSortSince
    }

    private func updateCounts() {
        if readingCount != readQueue.count { readingCount = readQueue.count }
        if sortingCount != sortQueue.count { sortingCount = sortQueue.count }
    }

    private var shouldPause: Bool {
        ScreenRecordingManager.shared.isActive
            || ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    private func schedulePublish() {
        guard publishTask == nil else { return }
        publishTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            publish()
        }
    }

    private func publish() {
        publishTask?.cancel()
        publishTask = nil
        guard !unpublished.isEmpty else { return }
        let changed = Set(unpublished.keys)
        analyses.merge(unpublished) { _, new in new }
        unpublished = [:]
        revision &+= 1
        CaptureLibraryModel.shared.indexDidChange(changed: changed)
    }

    private func observeHistory() {
        withObservationTracking {
            _ = ScreenshotHistoryStore.shared.items
            _ = RecordingProjectStore.shared.projects
        } onChange: {
            Task { @MainActor in
                CaptureLibraryModel.shared.refresh()
                CaptureLibraryIndex.shared.observeHistory()
            }
        }
    }
}

actor CaptureLibraryIndexStore {
    private let directory: URL
    private var pack: CaptureFeaturePrintPack

    private var unpackable: Set<CaptureFeaturePrintPack.Key> = []

    init(directory: URL) {
        self.directory = directory
        pack = CaptureFeaturePrintPack(url: directory.appendingPathComponent("Feature Prints.pack"))
    }

    func loadAll() -> [String: CaptureAnalysis] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        var result: [String: CaptureAnalysis] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let analysis = try? decoder.decode(CaptureAnalysis.self, from: data) else { continue }
            result[analysis.id] = analysis
        }
        return result
    }

    func save(_ analysis: CaptureAnalysis, featurePrint: Data?) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(analysis).write(to: url(analysis.id, "json"), options: .atomic)
            if let featurePrint {
                try featurePrint.write(to: url(analysis.id, "print"), options: .atomic)

                let key = CaptureFeaturePrintPack.key(analysis.id)
                unpackable.remove(key)
                if let elements = Self.elements(ofArchive: featurePrint) {
                    pack.open()
                    pack.append([(key, elements)])
                }
            }
        } catch {
            AppLog.event("library", "failed_to_save_library_index_entry", fields: ["error": AppLog.error(error)])
        }
    }

    func forgetFeaturePrints() {
        pack.close()
    }

    func remove(ids: [String]) {
        for id in ids {
            try? FileManager.default.removeItem(at: url(id, "json"))
            try? FileManager.default.removeItem(at: url(id, "print"))
        }
    }

    func nearest(to id: String, among candidates: [String], limit: Int) -> [String] {
        pack.open()
        let target = CaptureFeaturePrintPack.key(id)
        let keyed = candidates.map { ($0, CaptureFeaturePrintPack.key($0)) }

        var missing: [(CaptureFeaturePrintPack.Key, [Float])] = []
        for (candidate, key) in [(id, target)] + keyed where !pack.contains(key) && !unpackable.contains(key) {
            if let data = try? Data(contentsOf: url(candidate, "print")),
               let elements = Self.elements(ofArchive: data) {
                missing.append((key, elements))
            } else {
                unpackable.insert(key)
            }
        }
        pack.append(missing)
        return pack.nearest(to: target, among: keyed, limit: limit)
    }

    private static func elements(ofArchive data: Data) -> [Float]? {
        guard let observation = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data),
              observation.elementType == .float else { return nil }
        return observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func url(_ id: String, _ pathExtension: String) -> URL {
        let digest = SHA256.hash(data: Data(id.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension(pathExtension)
    }
}

nonisolated struct CaptureFeaturePrintPack {
    struct Key: Hashable {
        var high: UInt64
        var low: UInt64
    }

    private static let magic: UInt32 = 0x5046_4453
    private static let headerSize = 8
    private static let keySize = 16

    let url: URL
    private var data: Data?
    private var dimension = 0

    private var offsets: [Key: Int] = [:]
    private var recordCount = 0
    private var isOpen = false

    init(url: URL) {
        self.url = url
    }

    static func key(_ id: String) -> Key {
        SHA256.hash(data: Data(id.utf8)).withUnsafeBytes {
            Key(high: $0.loadUnaligned(as: UInt64.self), low: $0.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
        }
    }

    private var recordSize: Int { Self.keySize + dimension * MemoryLayout<Float>.size }

    func contains(_ key: Key) -> Bool { offsets[key] != nil }

    mutating func open() {
        guard !isOpen else { return }
        isOpen = true
        guard let mapped = try? Data(contentsOf: url, options: .alwaysMapped),
              mapped.count >= Self.headerSize else { return }
        let (magic, dimension) = mapped.withUnsafeBytes {
            ($0.loadUnaligned(as: UInt32.self), Int($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
        }
        guard magic == Self.magic, dimension > 0 else { return }
        self.dimension = dimension
        let size = recordSize
        mapped.withUnsafeBytes { bytes in
            var offset = Self.headerSize
            while offset + size <= bytes.count {
                let key = Key(high: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self),
                              low: bytes.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self))
                offsets[key] = offset + Self.keySize
                offset += size
                recordCount += 1
            }
        }
        data = mapped
        if recordCount > offsets.count * 2 + 256 { compact() }
    }

    mutating func close() {
        data = nil
        dimension = 0
        offsets = [:]
        recordCount = 0
        isOpen = false
    }

    mutating func append(_ entries: [(Key, [Float])]) {
        if dimension == 0, let first = entries.first { dimension = first.1.count }
        let entries = entries.filter { $0.1.count == dimension }
        guard !entries.isEmpty else { return }
        var bytes = Data()
        bytes.reserveCapacity((data == nil ? Self.headerSize : 0) + entries.count * recordSize)
        if data == nil {
            withUnsafeBytes(of: Self.magic) { bytes.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt32(dimension)) { bytes.append(contentsOf: $0) }
        }
        for (key, elements) in entries {
            withUnsafeBytes(of: key.high) { bytes.append(contentsOf: $0) }
            withUnsafeBytes(of: key.low) { bytes.append(contentsOf: $0) }
            elements.withUnsafeBytes { bytes.append(contentsOf: $0) }
        }
        do {
            if data == nil {
                try bytes.write(to: url, options: .atomic)
            } else {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: bytes)
            }
        } catch {

            try? FileManager.default.removeItem(at: url)
        }
        close()
        open()
    }

    func nearest(to targetKey: Key, among candidates: [(id: String, key: Key)], limit: Int) -> [String] {
        guard let data, let targetOffset = offsets[targetKey] else { return [] }
        let dimension = dimension
        return data.withUnsafeBytes { bytes -> [String] in
            func elements(at offset: Int) -> UnsafePointer<Float> {
                UnsafePointer((bytes.baseAddress! + offset).assumingMemoryBound(to: Float.self))
            }
            let target = elements(at: targetOffset)
            var scored: [(id: String, distance: Float)] = []
            scored.reserveCapacity(candidates.count)
            for candidate in candidates where candidate.key != targetKey {
                guard let offset = offsets[candidate.key] else { continue }
                var distance: Float = 0
                vDSP_distancesq(target, 1, elements(at: offset), 1, &distance, vDSP_Length(dimension))
                scored.append((candidate.id, distance))
            }
            return scored.sorted { $0.distance < $1.distance }.prefix(limit).map(\.id)
        }
    }

    private mutating func compact() {
        guard let data else { return }
        var bytes = Data(data.prefix(Self.headerSize))
        bytes.reserveCapacity(Self.headerSize + offsets.count * recordSize)
        for offset in offsets.values {
            bytes.append(data[(offset - Self.keySize)..<(offset + recordSize - Self.keySize)])
        }
        try? bytes.write(to: url, options: .atomic)
        close()
        open()
    }
}
