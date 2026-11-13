import AppKit
import SwiftUI
import Vision

struct CaptureFeedbackRenderBackdrop<Content: View>: View {
    let image: NSImage
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }
}

enum CaptureFeedbackRenderStates {
    static let textFeedback: [(String, CaptureTextFeedback)] = [
        ("success", .copied(text: "Capture a clear view of the work.")),
        ("success-multiline", .copied(text: "Release Overview: capture, annotate, and share a clear view of the work with everyone on the team.\nRecordings\nReview")),
        ("empty", .noTextFound),
        ("failure", .failure(title: "Text recognition failed")),
        ("failure-capture", .failure(title: "Capture failed")),
        ("failure-long", .failure(title: "Overlap is ambiguous. Select an area with more distinct content."))
    ]

    static let codeVariants = ["qr", "barcode", "links", "combined", "copied", "binary", "failure", "many"]

    private static let reviewLink = URL(string: "https://example.com/review")!

    static func codeFeedbackView(variant: String) -> CaptureCodeFeedbackView {
        let qrCode = DetectedCaptureCode(symbology: VNBarcodeSymbology.qr.rawValue, payload: reviewLink.absoluteString, data: nil)
        let barcode = DetectedCaptureCode(symbology: VNBarcodeSymbology.code128.rawValue, payload: "4006381333931", data: nil)
        let binaryCode = DetectedCaptureCode(symbology: VNBarcodeSymbology.qr.rawValue, payload: nil, data: Data((0..<48).map { UInt8($0 * 5 % 256) }))
        let detection: CaptureCodeDetection
        var copiedIdentifiers: Set<String> = []
        var failure: String?
        switch variant {
        case "qr":
            detection = CaptureCodeDetection(codes: [qrCode], links: [])
        case "barcode":
            detection = CaptureCodeDetection(codes: [barcode], links: [])
        case "links":
            detection = CaptureCodeDetection(codes: [], links: [reviewLink, URL(string: "https://example.com/docs/capture-text")!])
        case "combined":
            detection = CaptureCodeDetection(codes: [qrCode, barcode], links: [reviewLink, URL(string: "https://example.com/docs")!])
        case "copied":
            detection = CaptureCodeDetection(codes: [qrCode, barcode], links: [reviewLink])
            copiedIdentifiers = [barcode.id]
        case "binary":
            detection = CaptureCodeDetection(codes: [binaryCode], links: [])
        case "failure":
            detection = CaptureCodeDetection(codes: [], links: [reviewLink])
            failure = "The link could not be opened."
        default:
            detection = CaptureCodeDetection(
                codes: [qrCode, barcode],
                links: [reviewLink] + (1...8).map { URL(string: "https://example.com/releases/\($0)/notes")! }
            )
        }
        return CaptureCodeFeedbackView(
            detection: detection,
            maximumListHeight: 320,
            copiedIdentifiers: copiedIdentifiers,
            failure: failure,
            dismiss: {}
        )
    }
}
