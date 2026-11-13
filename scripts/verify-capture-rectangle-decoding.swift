import AppKit

@main
struct CaptureRectangleVerification {
    static func main() {
        let rectangle = CGRect(x: 1, y: 2, width: 3, height: 4)
        let values: [Any?] = [nil, rectangle, NSValue(rect: rectangle), rectangle.dictionaryRepresentation,
                              NSValue(range: NSRange(location: 0, length: 2)), NSNumber(value: 3), NSNull(),
                              ["X": "invalid"], [:] as [String: Any],
                              ["X": 1, "Y": 2, "Width": Double.nan, "Height": 4],
                              ["X": 1, "Y": Double.infinity, "Width": 3, "Height": 4],
                              ["X": NSNull(), "Y": 2, "Width": 3, "Height": 4]]
        for (index, value) in values.enumerated() {
            let result = CaptureRectangleDecoder.decode(value)
            precondition((result != nil) == [1, 2, 3].contains(index))
            if let result { precondition(result == rectangle) }
        }
        print("rectangle_verification outcome=verified accepted=3 rejected=9 malformed_values=rejected nonfinite_values=rejected")
    }
}
