import AppKit
import CoreMedia
import CoreVideo
import ImageIO
import IOSurface
import ScreenCaptureKit

enum UpshotPreferences {
    static let includeAppWindowsInCaptures = false
}

final class DesktopIconVisibilityService {
    static let shared = DesktopIconVisibilityService()
    var coverWindowIDs: Set<CGWindowID> { preconditionFailure("Screen access is forbidden during offline verification") }
    func beginCapture() async throws -> UUID? { preconditionFailure("Screen access is forbidden during offline verification") }
    func endCapture(_ token: UUID?) { preconditionFailure("Screen access is forbidden during offline verification") }
}

enum ActiveDisplayResolver {
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        preconditionFailure("Screen access is forbidden during offline verification")
    }
}

@main
struct AreaCaptureOfflineVerification {
    static func image(width: Int, height: Int, colors: [CGColor]) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (index, color) in colors.enumerated() {
            context.setFillColor(color)
            context.fill(CGRect(x: index % 2 * width / 2, y: index / 2 * height / 2, width: width / 2, height: height / 2))
        }
        return context.makeImage()!
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    static func write(_ image: CGImage, to url: URL) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
    }

    static func verifyFrameSelection(_ stored: AreaCaptureSnapshot) {
        var frames = AreaCaptureFrameRing<Int>()
        precondition(frames.selection(for: 10) == nil)
        frames.receive(0, presentedAt: 10)
        precondition(frames.selection(for: 10)?.frame.value == 0)
        frames.receive(1, presentedAt: 10 + 1.0 / 60)
        let afterOneFrame = frames.selection(for: 10.01)!
        precondition(afterOneFrame.frame.value == 0 && !afterOneFrame.usedOldestFallback)
        print("PASS frame arriving after event: selected the preceding frame")
        frames.receive(2, presentedAt: 10 + 2.0 / 60)
        frames.receive(3, presentedAt: 10 + 3.0 / 60)
        let afterSeveralFrames = frames.selection(for: 10.02)!
        precondition(afterSeveralFrames.frame.value == 1 && !afterSeveralFrames.usedOldestFallback)
        precondition(frames.selection(for: 10.01)?.frame.value == 0)
        print("PASS several frames arriving after event: selected the newest preceding frame")
        let fallback = frames.selection(for: 9.99)!
        precondition(fallback.frame.value == 0 && fallback.usedOldestFallback)
        precondition(abs((fallback.frame.presentationTime - 9.99) * 1000 - 10) < 0.000001)
        print("PASS no frame at or before event: oldest retained frame selected, gapMs=10.000")
        frames.receive(-1, presentedAt: 9)
        frames.receive(-1, presentedAt: .nan)
        frames.receive(-1, presentedAt: .infinity)
        frames.receive(-1, presentedAt: -1)
        precondition(frames.count == 4 && frames.newest?.value == 3)
        frames.receive(4, presentedAt: 10 + 3.0 / 60)
        precondition(frames.count == 4 && frames.newest?.value == 4)
        precondition(frames.selection(for: .nan) == nil)
        precondition(frames.selection(for: .infinity) == nil)
        frames.removeAll()
        precondition(frames.count == 0 && frames.newest == nil && frames.oldest == nil)
        print("PASS timestamp boundaries, duplicate replacement, out-of-order rejection, invalid timestamps, cleanup")
        for frequency in [60, 120, 240] {
            var history = AreaCaptureFrameRing<Int>(maximumFramesPerSecond: frequency)
            for index in 0..<5_000 {
                history.receive(index, presentedAt: 10 + Double(index) / Double(frequency))
                precondition(history.count <= history.capacity)
            }
            let newest = history.newest!.presentationTime
            precondition(newest - history.oldest!.presentationTime >= 0.25 - 0.000001)
            let selection = history.selection(for: newest - 0.25 + 0.000000001)!
            precondition(!selection.usedOldestFallback)
            precondition(selection.frame.value == 4_999 - frequency / 4)
            let oldestFallback = history.selection(for: history.oldest!.presentationTime - 0.001)!
            precondition(oldestFallback.usedOldestFallback)
            precondition(oldestFallback.frame.value == 5_000 - history.capacity)
            precondition(abs((oldestFallback.frame.presentationTime - (history.oldest!.presentationTime - 0.001)) * 1000 - 1) < 0.000001)
        }
        print("PASS bounded ring wraparound: at least 250 ms retained at 60, 120, and 240 frames per second")
        var storedFrames = AreaCaptureFrameRing<AreaCaptureSnapshot>()
        storedFrames.receive(stored, presentedAt: 10)
        storedFrames.receive(AreaCaptureSnapshot(displayID: 2, frame: stored.frame, image: stored.image), presentedAt: 10.02)
        precondition(storedFrames.selection(for: 10.01)?.frame.value.displayID == stored.displayID)
    }

    static func verifyBufferRetention() throws {
        var source: CVPixelBuffer?
        precondition(CVPixelBufferCreate(nil, 16, 12, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &source) == kCVReturnSuccess)
        let sourceBuffer = source!
        var frames = AreaCaptureFrameRing<CVPixelBuffer>()
        let pool = try AreaCaptureFrameBufferPool(width: 16, height: 12, maximumBufferCount: frames.capacity + 1)
        var surfaceIDs: Set<UInt32> = []
        for index in 0..<600 {
            precondition(CVPixelBufferLockBaseAddress(sourceBuffer, []) == kCVReturnSuccess)
            let bytes = CVPixelBufferGetBaseAddress(sourceBuffer)!.assumingMemoryBound(to: UInt8.self)
            for row in 0..<12 {
                for column in 0..<16 {
                    let offset = row * CVPixelBufferGetBytesPerRow(sourceBuffer) + column * 4
                    bytes[offset] = 0
                    bytes[offset + 1] = UInt8(index / 251)
                    bytes[offset + 2] = UInt8(index % 251)
                    bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(sourceBuffer, [])
            let retained = try pool.copy(sourceBuffer)
            precondition(retained !== sourceBuffer)
            let surface = CVPixelBufferGetIOSurface(retained)!.takeUnretainedValue()
            surfaceIDs.insert(IOSurfaceGetID(surface))
            frames.receive(retained, presentedAt: 10 + Double(index) / 60)
            precondition(frames.count <= frames.capacity)
        }
        precondition(surfaceIDs.count <= pool.maximumBufferCount)
        let eventTime = 10 + 592.25 / 60
        let selected = frames.selection(for: eventTime)!
        precondition(!selected.usedOldestFallback)
        precondition(abs(selected.frame.presentationTime - (10 + 592.0 / 60)) < 0.000001)
        let selectedPixels = pixels(try AreaCaptureFrameStream.image(from: selected.frame.value))
        precondition(Array(selectedPixels.prefix(4)) == [UInt8(592 % 251), UInt8(592 / 251), 0, 255])
        print("PASS IOSurface retention: 600 producer updates, independent pixels, bounded pool reuse, historical frame conversion")
        let exhaustedPool = try AreaCaptureFrameBufferPool(width: 16, height: 12, maximumBufferCount: 2)
        let first = try exhaustedPool.copy(sourceBuffer)
        let second = try exhaustedPool.copy(sourceBuffer)
        withExtendedLifetime((first, second)) {
            do {
                _ = try exhaustedPool.copy(sourceBuffer)
                preconditionFailure("Pixel buffer allocation must remain bounded")
            } catch {}
        }
        frames.removeAll()
        precondition(frames.count == 0)
        print("PASS IOSurface allocation threshold and ring release")
    }

    static func verifySampleConversion() throws {
        var allocatedBuffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(nil, 8, 6, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &allocatedBuffer) == kCVReturnSuccess)
        let buffer = allocatedBuffer!
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<6 {
            for x in 0..<8 {
                let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
                bytes[offset] = 0
                bytes[offset + 1] = 0
                bytes[offset + 2] = 255
                bytes[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        precondition(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: 12, preferredTimescale: 600), decodeTimeStamp: .invalid)
        var allocatedSample: CMSampleBuffer?
        precondition(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &allocatedSample) == noErr)
        let sample = allocatedSample!
        precondition(AreaCaptureFrameStream.presentationTime(of: sample) == 12)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)!
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        let key = SCStreamFrameInfo.displayTime.rawValue as NSString
        let ticks = NSNumber(value: CMClockConvertHostTimeToSystemUnits(CMTime(seconds: 13, preferredTimescale: 1_000_000_000)))
        CFDictionarySetValue(dictionary, Unmanaged.passUnretained(key).toOpaque(), Unmanaged.passUnretained(ticks).toOpaque())
        precondition(abs(AreaCaptureFrameStream.presentationTime(of: sample)! - 13) < 0.000001)
        let image = try AreaCaptureFrameStream.image(from: sample)
        precondition(image.width == 8 && image.height == 6)
        let bytesAfterConversion = pixels(image)
        for index in stride(from: 0, to: bytesAfterConversion.count, by: 4) {
            precondition(bytesAfterConversion[index] == 255 && bytesAfterConversion[index + 1] == 0 && bytesAfterConversion[index + 2] == 0 && bytesAfterConversion[index + 3] == 255)
        }
        print("PASS stream buffer conversion: BGRA pixels, displayTime host-clock conversion, sample presentation timestamp fallback")
    }

    static func main() throws {
        let windowConfiguration = AreaCaptureWindowSnapshot.configuration(includeShadow: false)
        precondition(windowConfiguration.ignoreShadows && !windowConfiguration.includeChildWindows && !windowConfiguration.showsCursor)
        print("PASS isolated window screenshot configuration: shadows disabled, child windows excluded, cursor excluded")
        let shadowConfiguration = AreaCaptureWindowSnapshot.configuration(includeShadow: true)
        precondition(!shadowConfiguration.ignoreShadows && !shadowConfiguration.includeChildWindows && !shadowConfiguration.showsCursor)
        print("PASS shadowed window screenshot configuration: shadows enabled without child windows")
        let output = URL(fileURLWithPath: ".local/verification/area-capture", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let source = image(width: 80, height: 60, colors: [red, green, blue, white])
        let frameURL = output.appendingPathComponent("stored-frame.png")
        write(source, to: frameURL)
        let loaded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(frameURL as CFURL, nil)!, 0, nil)!
        let stored = AreaCaptureSnapshot(displayID: 1, frame: CGRect(x: -40, y: 20, width: 40, height: 30), image: loaded, presentationTime: 10)
        verifyFrameSelection(stored)
        try verifyBufferRetention()
        try verifySampleConversion()
        var frames = AreaCaptureFrameRing<AreaCaptureSnapshot>()
        frames.receive(stored, presentedAt: 10)
        let chosen = frames.selection(for: 10.01)!.frame.value
        frames.receive(AreaCaptureSnapshot(displayID: 1, frame: stored.frame,
                                           image: image(width: 80, height: 60, colors: [white, white, white, white]), presentationTime: 10.02),
                       presentedAt: 10.02)
        let full = try AreaCaptureSnapshot.composite([chosen], in: stored.frame)
        precondition(pixels(full) == pixels(loaded))
        let rect = CGRect(x: -25, y: 25, width: 15, height: 20)
        let cropped = try AreaCaptureSnapshot.composite([chosen], in: rect)
        let expected = loaded.cropping(to: CGRect(x: 30, y: 10, width: 30, height: 40))!
        precondition(cropped.width == 30 && cropped.height == 40 && pixels(cropped) == pixels(expected))
        write(cropped, to: output.appendingPathComponent("stored-frame-crop.png"))
        print("PASS stored frame composition: PNG round trip, exact pixels, negative display origin, 2x scale, asymmetric crop")
        let second = AreaCaptureSnapshot(displayID: 2, frame: CGRect(x: 0, y: 20, width: 40, height: 30),
                                         image: image(width: 40, height: 30, colors: [blue, blue, blue, blue]), presentationTime: 10.005)
        let spanning = try AreaCaptureSnapshot.composite([chosen, second], in: CGRect(x: -10, y: 24, width: 20, height: 8))
        precondition(spanning.width == 40 && spanning.height == 16)
        let data = pixels(spanning)
        let firstPixels = pixels(loaded)
        let firstOffset = (45 * 80 + 60) * 4
        let firstColor = Array(firstPixels[firstOffset..<firstOffset + 4])
        let secondColor = Array(pixels(second.image).prefix(4))
        precondition(firstColor != secondColor)
        for y in 0..<16 {
            for x in 0..<40 {
                let offset = (y * 40 + x) * 4
                let expectedPixel = x < 20 ? firstColor : secondColor
                precondition(Array(data[offset..<offset + 4]) == expectedPixel,
                             "Pixel x=\(x) y=\(y): actual=\(Array(data[offset..<offset + 4])) expected=\(expectedPixel)")
            }
        }
        write(spanning, to: output.appendingPathComponent("mixed-scale-composition.png"))
        do {
            _ = try AreaCaptureSnapshot.composite([chosen], in: CGRect(x: 100, y: 100, width: 4, height: 4))
            preconditionFailure("A selection outside every display must fail")
        } catch {}
        print("PASS multiple display composition: mixed 1x and 2x displays, seam pixels, output size, no intersection rejection")
        print("OFFLINE VERIFICATION PASSED; no app launch, selector, stream start, desktop cover, or screen acquisition")
    }
}
