import Foundation

/// An ISO 4217 currency code, always uppercase ("USD"). Providers send "usd" or "USD"; both become "USD".
public struct Currency: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let code: String

    public init(_ code: String) {
        self.code = code.trimmingCharacters(in: .whitespaces).uppercased()
    }

    public static let usd = Currency("USD")

    public var description: String { code }

    public static func < (lhs: Currency, rhs: Currency) -> Bool { lhs.code < rhs.code }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}

/// An amount of money. Always `Decimal`, never `Double`: spend is summed from many small line items, and
/// binary floating point drifts.
public struct Money: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var amount: Decimal
    public var currency: Currency

    public init(_ amount: Decimal, _ currency: Currency = .usd) {
        self.amount = amount
        self.currency = currency
    }

    public static func zero(_ currency: Currency = .usd) -> Money { Money(0, currency) }

    /// Parses a decimal string exactly ("12.345678"). Nil for anything that isn't a plain number.
    public init?(_ text: String, _ currency: Currency = .usd) {
        guard let amount = Money.decimal(text) else { return nil }
        self.init(amount, currency)
    }

    /// A string in the currency's smallest unit, as Anthropic sends it: "123.45" cents is $1.2345.
    public static func fromMinorUnits(_ text: String, _ currency: Currency = .usd) -> Money? {
        guard let minor = decimal(text) else { return nil }
        return Money(minor / 100, currency)
    }

    /// An integer number of cents, as OpenAI, Neon and Cloudflare send limits.
    public static func fromCents(_ cents: Int, _ currency: Currency = .usd) -> Money {
        Money(Decimal(cents) / 100, currency)
    }

    /// Strict decimal parsing: optional sign, digits, optional fraction, optional exponent. Locale-independent.
    public static func decimal(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil
        else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Adds two amounts in the same currency. Mixing currencies is a programming error, so it traps in
    /// debug and keeps the left side in release; use `MoneyTotals` to sum mixed currencies.
    public static func + (lhs: Money, rhs: Money) -> Money {
        assert(lhs.currency == rhs.currency, "Adding \(lhs.currency) to \(rhs.currency)")
        guard lhs.currency == rhs.currency else { return lhs }
        return Money(lhs.amount + rhs.amount, lhs.currency)
    }

    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.currency == rhs.currency ? lhs.amount < rhs.amount : lhs.currency < rhs.currency
    }

    /// Rounded to cents, half away from zero, the way an invoice rounds.
    public var rounded: Money {
        var value = amount
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return Money(result, currency)
    }

    public var description: String { MoneyText.string(self) }
}

/// Sums that may hold more than one currency. Kill Cord never converts currencies: a total in USD and EUR
/// shows both.
public struct MoneyTotals: Hashable, Sendable, Codable {
    public private(set) var byCurrency: [Currency: Decimal] = [:]

    public init() {}

    public init(_ amounts: [Money]) {
        amounts.forEach { add($0) }
    }

    public mutating func add(_ money: Money) {
        byCurrency[money.currency, default: 0] += money.amount
    }

    /// Amounts sorted by currency, USD first.
    public var amounts: [Money] {
        byCurrency.map { Money($0.value, $0.key) }.sorted { lhs, rhs in
            if lhs.currency == .usd { return rhs.currency != .usd }
            if rhs.currency == .usd { return false }
            return lhs.currency < rhs.currency
        }
    }

    public var isEmpty: Bool { byCurrency.isEmpty }

    public func amount(in currency: Currency) -> Money? {
        byCurrency[currency].map { Money($0, currency) }
    }
}

/// Formats money for people: "$1,234.56", "$0.42", "EUR 12.00". Locale-independent so the menu bar, tests,
/// and notifications agree.
public enum MoneyText {
    public static func string(_ money: Money) -> String {
        let rounded = money.rounded
        let negative = rounded.amount < 0
        let magnitude = negative ? -rounded.amount : rounded.amount
        let digits = fixed(magnitude)
        let prefix = money.currency == .usd ? "$" : "\(money.currency.code) "
        return (negative ? "-" : "") + prefix + digits
    }

    /// Short form for the menu bar: "$12", "$1.2k", "$48k". Under $100 keeps cents.
    public static func compact(_ money: Money) -> String {
        let value = money.rounded.amount
        let prefix = money.currency == .usd ? "$" : "\(money.currency.code) "
        if value < 100 { return string(money) }
        if value < 1000 { return prefix + whole(value) }
        let thousands = value / 1000
        if thousands < 10 { return prefix + oneDecimal(thousands) + "k" }
        return prefix + whole(thousands) + "k"
    }

    public static func string(_ totals: MoneyTotals) -> String {
        guard !totals.isEmpty else { return string(.zero()) }
        return totals.amounts.map(string).joined(separator: " + ")
    }

    /// "1234.5" -> "1,234.50".
    static func fixed(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(parts[0])
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        while fraction.count < 2 { fraction += "0" }
        return grouped(integer) + "." + fraction
    }

    private static func whole(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return grouped(NSDecimalNumber(decimal: rounded).stringValue)
    }

    private static func oneDecimal(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 1, .plain)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        return text.contains(".") ? text : text + ".0"
    }

    private static func grouped(_ integer: String) -> String {
        var result = ""
        for (index, character) in integer.reversed().enumerated() {
            if index > 0, index % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return String(result.reversed())
    }
}

/// Decodes a money amount that a provider may send as a JSON number or as a string. Numbers are read
/// through `Decimal` directly, never through `Double`.
struct FlexibleDecimal: Decodable, Sendable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            if text.isEmpty {
                value = 0
                return
            }
            guard let parsed = Money.decimal(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a decimal string")
            }
            value = parsed
        } else {
            value = try container.decode(Decimal.self)
        }
    }
}
