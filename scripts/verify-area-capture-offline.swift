import AppKit
import CoreMedia
import ImageIO
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
        var latest = AreaCaptureLatestFrame<AreaCaptureSnapshot>()
        precondition(latest.frame(atOrBefore: 10) == nil)
        latest.receive(stored, presentedAt: 10)
        precondition(latest.frame(atOrBefore: 10)?.displayID == stored.displayID)
        precondition(latest.frame(atOrBefore: 10.01)?.displayID == stored.displayID)
        precondition(latest.frame(atOrBefore: 9.99) == nil)
        latest.receive(AreaCaptureSnapshot(displayID: 2, frame: stored.frame, image: stored.image), presentedAt: 11)
        precondition(latest.frame(atOrBefore: 11)?.displayID == 2)
        precondition(latest.frame(atOrBefore: 10.5) == nil)
        latest.receive(stored, presentedAt: 9)
        latest.receive(stored, presentedAt: .nan)
        latest.receive(stored, presentedAt: .infinity)
        latest.receive(stored, presentedAt: -1)
        precondition(latest.frame(atOrBefore: 11)?.displayID == 2)
        precondition(latest.frame(atOrBefore: .nan) == nil)
        print("PASS timestamp selection: exact boundary, earlier frame, future rejection, latest replacement, out-of-order rejection, invalid timestamps")
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
        try verifySampleConversion()
        var latest = AreaCaptureLatestFrame<AreaCaptureSnapshot>()
        latest.receive(stored, presentedAt: 10)
        let chosen = latest.frame(atOrBefore: 10.01)!
        latest.receive(AreaCaptureSnapshot(displayID: 1, frame: stored.frame,
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
