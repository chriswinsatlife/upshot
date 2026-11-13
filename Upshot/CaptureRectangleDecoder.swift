import CoreGraphics
import Foundation

nonisolated enum CaptureRectangleDecoder {
    static func decode(_ value: Any?) -> CGRect? {
        let rectangle: CGRect
        if let dictionary = value as? [String: Any] {
            guard let x = dictionary["X"] as? NSNumber,
                  let y = dictionary["Y"] as? NSNumber,
                  let width = dictionary["Width"] as? NSNumber,
                  let height = dictionary["Height"] as? NSNumber else { return nil }
            rectangle = CGRect(x: x.doubleValue, y: y.doubleValue, width: width.doubleValue, height: height.doubleValue)
        } else if let value = value as? CGRect {
            rectangle = value
        } else {
            return nil
        }
        guard rectangle.origin.x.isFinite, rectangle.origin.y.isFinite,
              rectangle.size.width.isFinite, rectangle.size.height.isFinite else { return nil }
        return rectangle
    }
}
