import Foundation

/// A small path into a JSON response, for custom connections: `data.balance`, `tasks.0.result.0.money`,
/// `$.items[0].value`. Object keys and array indexes only; no filters or wildcards.
public struct JSONPath: Sendable, Equatable {
    public let steps: [Step]

    public enum Step: Sendable, Equatable {
        case key(String)
        case index(Int)
    }

    /// Nil for an empty or malformed path.
    public init?(_ text: String) {
        var body = text.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("$") { body.removeFirst() }
        if body.hasPrefix(".") { body.removeFirst() }
        body = body.replacingOccurrences(of: "[", with: ".").replacingOccurrences(of: "]", with: "")
        guard !body.isEmpty, body.count <= 300 else { return nil }
        var steps: [Step] = []
        for part in body.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty else { return nil }
            if let index = Int(part), index >= 0 { steps.append(.index(index)) } else { steps.append(.key(String(part))) }
        }
        self.steps = steps
    }

    /// The value at the path in a parsed JSON object, or nil when any step is missing.
    public func value(in root: Any) -> Any? {
        var current: Any = root
        for step in steps {
            switch step {
            case .key(let key):
                guard let object = current as? [String: Any], let next = object[key] else { return nil }
                current = next
            case .index(let index):
                if let array = current as? [Any] {
                    guard index < array.count else { return nil }
                    current = array[index]
                } else if let object = current as? [String: Any], let next = object[String(index)] {
                    current = next
                } else {
                    return nil
                }
            }
        }
        return current is NSNull ? nil : current
    }

    /// A number at the path, from a JSON number or a numeric string. Exact for decimal strings.
    public func decimal(in root: Any) -> Decimal? {
        JSONPath.decimal(value(in: root))
    }

    static func decimal(_ value: Any?) -> Decimal? {
        switch value {
        case let text as String: return Money.decimal(text)
        case let number as NSNumber:
            // Booleans arrive as NSNumber too; they aren't amounts.
            if String(cString: number.objCType) == "c" { return nil }
            return Money.decimal(number.stringValue)
        default: return nil
        }
    }

    /// A date at the path: ISO 8601, "2026-12-01", or Unix seconds (milliseconds when it's that large).
    public func date(in root: Any) -> Date? {
        let raw = value(in: root)
        if let text = raw as? String {
            if let date = ISO8601.date(text) { return date }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: text) { return date }
        }
        guard let seconds = JSONPath.decimal(raw).map({ NSDecimalNumber(decimal: $0).doubleValue }), seconds > 0
        else { return nil }
        return Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds)
    }
}
