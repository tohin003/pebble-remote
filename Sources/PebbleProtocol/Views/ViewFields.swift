import Foundation

/// Reads one object of a view, field by field, each checked against its type and bound in pebble-ui-spec v1. A field
/// that fails its check is left out, as Pebble's own windows do (workView.ts `record`), and fields this version does not
/// know are never read (rule 2).
struct ViewFields: Sendable {
    let object: [String: JSONValue]

    init?(_ json: JSONValue?) {
        guard let object = json?.object else { return nil }
        self.object = object
    }

    func has(_ key: String) -> Bool { object[key] != nil && object[key] != .null }

    /// A string, clamped to `limit` characters (`ViewText`); nil when absent, not a string, or empty once cleaned.
    func text(_ key: String, _ limit: Int, multiline: Bool = false) -> String? {
        object[key]?.string.flatMap { ViewText.clamp($0, limit, multiline: multiline) }
    }

    /// A whole number of zero or more (JavaScript's `Number.isSafeInteger(raw) && raw >= 0`).
    func count(_ key: String) -> Int? {
        object[key].flatMap(Self.wholeNumber)
    }

    static func wholeNumber(_ value: JSONValue) -> Int? {
        switch value {
        case .int(let number): number >= 0 ? number : nil
        case .double(let number):
            number.isFinite && number >= 0 && number.rounded() == number && number < 9_007_199_254_740_992 ? Int(number) : nil
        default: nil
        }
    }

    /// A finite number of zero or more.
    func amount(_ key: String) -> Double? {
        guard let number = object[key]?.double, number.isFinite, number >= 0 else { return nil }
        return number
    }

    /// Any finite number within `limit` either side of zero (native views' values and deltas).
    func number(_ key: String, limit: Double = 1e15) -> Double? {
        object[key].flatMap { Self.finite($0, limit: limit) }
    }

    static func finite(_ value: JSONValue, limit: Double = 1e15) -> Double? {
        guard let number = value.double, number.isFinite, abs(number) <= limit else { return nil }
        return number
    }

    func flag(_ key: String) -> Bool? { object[key]?.bool }

    /// One of a fixed set of words.
    func word<Value: RawRepresentable>(_ key: String, as type: Value.Type = Value.self) -> Value?
    where Value.RawValue == String {
        object[key]?.string.flatMap(Value.init(rawValue:))
    }

    /// A list of strings, the first `max` kept, each clamped; empty strings dropped. Nil when it isn't a list.
    func texts(_ key: String, max: Int, limit: Int) -> [String]? {
        guard let list = object[key]?.array else { return nil }
        return list.prefix(max).compactMap { $0.string.flatMap { ViewText.clamp($0, limit) } }
    }

    func list(_ key: String) -> [JSONValue]? { object[key]?.array }

    func nested(_ key: String) -> ViewFields? { ViewFields(object[key]) }

    /// Pebble's short identifiers (`^[A-Za-z0-9_-]{1,40}$`), never one of JavaScript's reserved names.
    func identifier(_ key: String) -> String? {
        object[key]?.string.flatMap { Self.checkedIdentifier($0) }
    }

    static func checkedIdentifier(_ value: String) -> String? {
        guard (1...40).contains(value.utf8.count), !reserved.contains(value) else { return nil }
        let allowed = value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2D: true
            default: false
            }
        }
        return allowed ? value : nil
    }

    static let reserved: Set<String> = ["__proto__", "prototype", "constructor", "__text"]
}
