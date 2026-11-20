import Foundation

/// This object is responsible for reading a number out of a `JSONSerialization` result the same way
/// on every Foundation: Apple's gives `NSNumber`, while swift-corelibs-foundation (Windows, Linux)
/// may give plain `Int` or `Double` that do not cast to `NSNumber`.
enum JSONNumber {
    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let number as NSNumber: return number.doubleValue
        default: return nil
        }
    }
}
