import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ScrollingCaptureOutputLimits {
    static let maximumHeight = 32_000
    static let maximumPixelCount = 200_000_000

    static func maximumHeight(forWidth width: Int) -> Int {
        guard width > 0 else { return 0 }
        return min(maximumHeight, maximumPixelCount / width)
    }
}

nonisolated struct ScrollingCaptureRaster: Sendable {
    let width: Int
    let height: Int
    let pixels: Data

    init(image: CGImage) throws {
        width = image.width
        height = image.height
        guard width > 0, height >= 8,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw ScrollingCaptureError.invalidImage }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = Data(bytes: data, count: width * height * 4)
    }

    func rowHashes() -> [UInt64] {
        pixels.withUnsafeBytes { bytes in
            let bytes = bytes.bindMemory(to: UInt8.self)
            let margin = width >= 64 ? max(1, width / 50) : 0
            let stride = max(1, (width - margin * 2) / 128)
            return (0..<height).map { row in
                var hash: UInt64 = 14_695_981_039_346_656_037
                for column in Swift.stride(from: margin, to: width - margin, by: stride) {
                    let offset = (row * width + column) * 4
                    for channel in 0..<3 {
                        hash = (hash ^ UInt64(bytes[offset + channel])) &* 1_099_511_628_211
                    }
                }
                return hash
            }
        }
    }

    func image() throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw ScrollingCaptureError.invalidImage
        }
        return image
    }

    init(width: Int, height: Int, pixels: Data) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

nonisolated enum ScrollingCaptureError: LocalizedError {
    case invalidImage
    case dimensionsChanged
    case unverifiedOverlap
    case ambiguousOverlap
    case displayChanged
    case maximumLengthReached

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The captured image could not be processed."
        case .dimensionsChanged: "The capture dimensions changed. Stop to save the captured image."
        case .unverifiedOverlap: "Overlap unavailable. Scroll back slowly, then press Start."
        case .ambiguousOverlap: "Overlap is ambiguous. Select an area with more distinct content."
        case .displayChanged: "The display arrangement changed. Start a new scrolling capture."
        case .maximumLengthReached: "Maximum length reached"
        }
    }
}

nonisolated struct ScrollingCaptureStitcher: Sendable {
    struct Update: Sendable {
        enum Kind: String, Sendable {
            case firstFrame
            case appended
            case unchanged
            case reversed
            case maximumLengthReached
        }

        let kind: Kind
        let height: Int
        let addedRows: Int
        let overlapRows: Int
        let meanError: Double
    }

    private struct Match {
        let displacement: Int
        let error: Double
        let contentRows: Range<Int>
    }

    private(set) var width = 0
    private(set) var height = 0
    private(set) var frameCount = 0
    private var previous: ScrollingCaptureRaster?
    private var previousHashes: [UInt64] = []
    private var strips: [Data] = []
    private var footer = Data()

    mutating func append(_ image: CGImage) throws -> Update {
        if let previous, image.width != width || image.height != previous.height {
            throw ScrollingCaptureError.dimensionsChanged
        }
        let maximumHeight = ScrollingCaptureOutputLimits.maximumHeight(forWidth: image.width)
        guard image.height <= maximumHeight else { throw ScrollingCaptureError.maximumLengthReached }
        if previous != nil, height >= maximumHeight {
            return Update(kind: .maximumLengthReached, height: height, addedRows: 0, overlapRows: 0, meanError: 0)
        }
        let current = try ScrollingCaptureRaster(image: image)
        guard let previous else {
            width = current.width
            height = current.height
            frameCount = 1
            self.previous = current
            previousHashes = current.rowHashes()
            strips = [current.pixels]
            return Update(kind: height == maximumHeight ? .maximumLengthReached : .firstFrame,
                          height: height, addedRows: height, overlapRows: 0, meanError: 0)
        }
        if current.pixels == previous.pixels {
            return Update(kind: .unchanged, height: height, addedRows: 0, overlapRows: current.height, meanError: 0)
        }
        let hashes = current.rowHashes()
        let match = try Self.register(previous: previous, current: current, previousHashes: previousHashes, currentHashes: hashes)
        let overlap = match.contentRows.count - abs(match.displacement)
        guard match.displacement > 0 else {
            return Update(kind: match.displacement == 0 ? .unchanged : .reversed, height: height,
                          addedRows: 0, overlapRows: overlap, meanError: match.error)
        }
        let addedRows = min(match.displacement, maximumHeight - height)
        let rowBytes = width * 4
        let footerRows = current.height - match.contentRows.upperBound
        let previousFooterRows = footer.count / rowBytes
        if footerRows > previousFooterRows {
            removeTrailingBytes((footerRows - previousFooterRows) * rowBytes)
        } else if footerRows < previousFooterRows {
            let firstByte = (previous.height - previousFooterRows) * rowBytes
            let lastByte = match.contentRows.upperBound * rowBytes
            strips.append(previous.pixels.subdata(in: firstByte..<lastByte))
        }
        let lastByte = match.contentRows.upperBound * rowBytes
        let firstByte = lastByte - match.displacement * rowBytes
        strips.append(current.pixels.subdata(in: firstByte..<(firstByte + addedRows * rowBytes)))
        footer = current.pixels.subdata(in: lastByte..<current.pixels.count)
        height += addedRows
        frameCount += 1
        self.previous = current
        previousHashes = hashes
        if match.contentRows.lowerBound > 0 || footerRows > 0 {
            NSLog("Scrolling capture fixed rows verified: headerRows=%ld footerRows=%ld", match.contentRows.lowerBound, footerRows)
        }
        return Update(kind: height == maximumHeight ? .maximumLengthReached : .appended,
                      height: height, addedRows: addedRows, overlapRows: overlap, meanError: match.error)
    }

    func image() throws -> CGImage {
        guard frameCount > 0 else { throw ScrollingCaptureError.invalidImage }
        guard height <= ScrollingCaptureOutputLimits.maximumHeight(forWidth: width) else {
            throw ScrollingCaptureError.maximumLengthReached
        }
        var pixels = Data()
        pixels.reserveCapacity(width * height * 4)
        for strip in strips { pixels.append(strip) }
        pixels.append(footer)
        return try ScrollingCaptureRaster(width: width, height: height, pixels: pixels).image()
    }

    private mutating func removeTrailingBytes(_ count: Int) {
        var remaining = count
        while remaining > 0, let strip = strips.popLast() {
            if strip.count > remaining {
                strips.append(strip.subdata(in: 0..<(strip.count - remaining)))
                remaining = 0
            } else {
                remaining -= strip.count
            }
        }
    }

    private static func scrollingRows(previous: ScrollingCaptureRaster, current: ScrollingCaptureRaster) -> Range<Int> {
        previous.pixels.withUnsafeBytes { previousData in
            current.pixels.withUnsafeBytes { currentData in
                let rowBytes = previous.width * 4
                var firstRow = 0
                var lastRow = previous.height
                while firstRow < lastRow,
                      memcmp(previousData.baseAddress! + firstRow * rowBytes, currentData.baseAddress! + firstRow * rowBytes, rowBytes) == 0 {
                    firstRow += 1
                }
                while lastRow > firstRow,
                      memcmp(previousData.baseAddress! + (lastRow - 1) * rowBytes, currentData.baseAddress! + (lastRow - 1) * rowBytes, rowBytes) == 0 {
                    lastRow -= 1
                }
                return firstRow..<lastRow
            }
        }
    }

    private static func register(previous: ScrollingCaptureRaster, current: ScrollingCaptureRaster,
                                 previousHashes: [UInt64], currentHashes: [UInt64]) throws -> Match {
        let contentRows = scrollingRows(previous: previous, current: current)
        let minimumOverlap = max(4, min(64, contentRows.count / 8))
        guard contentRows.count > minimumOverlap else { throw ScrollingCaptureError.unverifiedOverlap }
        let maximumDisplacement = contentRows.count - minimumOverlap
        var rows: [UInt64: [Int]] = [:]
        for row in contentRows { rows[previousHashes[row], default: []].append(row) }
        var votes: [Int: Int] = [:]
        for row in contentRows {
            guard let matchingRows = rows[currentHashes[row]], matchingRows.count <= 8 else { continue }
            for matchingRow in matchingRows {
                let displacement = matchingRow - row
                if abs(displacement) <= maximumDisplacement { votes[displacement, default: 0] += 1 }
            }
        }
        var candidates = votes.sorted {
            $0.value == $1.value ? abs($0.key) < abs($1.key) : $0.value > $1.value
        }.prefix(16).map(\.key)
        if candidates.isEmpty {
            candidates = coarseCandidates(previous: previous, current: current, contentRows: contentRows, maximumDisplacement: maximumDisplacement)
        }
        if !candidates.contains(0) { candidates.append(0) }
        let matches = candidates.compactMap { displacement -> Match? in
            guard let error = verifiedError(previous: previous, current: current, contentRows: contentRows, displacement: displacement) else { return nil }
            return Match(displacement: displacement, error: error, contentRows: contentRows)
        }.sorted { $0.error < $1.error }
        guard let best = matches.first else { throw ScrollingCaptureError.unverifiedOverlap }
        if matches.dropFirst().contains(where: { abs($0.error - best.error) < 0.001 }) {
            throw ScrollingCaptureError.ambiguousOverlap
        }
        return best
    }

    private static func coarseCandidates(previous: ScrollingCaptureRaster, current: ScrollingCaptureRaster,
                                         contentRows: Range<Int>, maximumDisplacement: Int) -> [Int] {
        previous.pixels.withUnsafeBytes { previousBytes in
            current.pixels.withUnsafeBytes { currentBytes in
                let previousBytes = previousBytes.bindMemory(to: UInt8.self)
                let currentBytes = currentBytes.bindMemory(to: UInt8.self)
                let columnStep = max(1, previous.width / 48)
                var scores: [(Int, Double)] = []
                for displacement in -maximumDisplacement...maximumDisplacement {
                    let overlap = contentRows.count - abs(displacement)
                    let previousStart = contentRows.lowerBound + max(0, displacement)
                    let currentStart = contentRows.lowerBound + max(0, -displacement)
                    let rowStep = max(1, overlap / 32)
                    var difference = 0
                    var count = 0
                    for row in Swift.stride(from: 0, to: overlap, by: rowStep) {
                        for column in Swift.stride(from: 0, to: previous.width, by: columnStep) {
                            let left = ((previousStart + row) * previous.width + column) * 4
                            let right = ((currentStart + row) * previous.width + column) * 4
                            for channel in 0..<3 {
                                difference += abs(Int(previousBytes[left + channel]) - Int(currentBytes[right + channel]))
                                count += 1
                            }
                        }
                    }
                    scores.append((displacement, Double(difference) / Double(count)))
                }
                return scores.sorted { $0.1 < $1.1 }.prefix(16).map(\.0)
            }
        }
    }

    private static func verifiedError(previous: ScrollingCaptureRaster, current: ScrollingCaptureRaster,
                                      contentRows: Range<Int>, displacement: Int) -> Double? {
        let overlap = contentRows.count - abs(displacement)
        let previousStart = contentRows.lowerBound + max(0, displacement)
        let currentStart = contentRows.lowerBound + max(0, -displacement)
        let margin = previous.width >= 64 ? max(1, previous.width / 50) : 0
        let comparedWidth = previous.width - margin * 2
        let pixelCount = comparedWidth * overlap
        let maximumChangedPixels = max(1, pixelCount / 100)
        return previous.pixels.withUnsafeBytes { previousData in
            current.pixels.withUnsafeBytes { currentData -> Double? in
                let previousBytes = previousData.bindMemory(to: UInt8.self)
                let currentBytes = currentData.bindMemory(to: UInt8.self)
                var difference = 0
                var changedPixels = 0
                for row in 0..<overlap {
                    let previousOffset = ((previousStart + row) * previous.width + margin) * 4
                    let currentOffset = ((currentStart + row) * previous.width + margin) * 4
                    if memcmp(previousData.baseAddress! + previousOffset, currentData.baseAddress! + currentOffset, comparedWidth * 4) == 0 { continue }
                    for column in 0..<comparedWidth {
                        let left = previousOffset + column * 4
                        let right = currentOffset + column * 4
                        var maximumDifference = 0
                        for channel in 0..<4 {
                            let delta = abs(Int(previousBytes[left + channel]) - Int(currentBytes[right + channel]))
                            difference += delta
                            maximumDifference = max(maximumDifference, delta)
                        }
                        if maximumDifference > 12 { changedPixels += 1 }
                        if changedPixels > maximumChangedPixels { return nil }
                    }
                }
                let error = Double(difference) / Double(pixelCount * 4 * 255)
                return error <= 0.008 ? error : nil
            }
        }
    }
}

actor ScrollingCaptureProcessor {
    struct SavedImage: Sendable {
        let width: Int
        let height: Int
        let frameCount: Int
    }

    private var stitcher = ScrollingCaptureStitcher()

    func append(_ image: CGImage) throws -> ScrollingCaptureStitcher.Update {
        try stitcher.append(image)
    }

    func image() throws -> CGImage {
        try stitcher.image()
    }

    func writePNG(to url: URL, scale: CGFloat) throws -> SavedImage {
        let image = try stitcher.image()
        try Task.checkCancellation()
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        if Task.isCancelled {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            throw CancellationError()
        }
        return SavedImage(width: image.width, height: image.height, frameCount: stitcher.frameCount)
    }
}
