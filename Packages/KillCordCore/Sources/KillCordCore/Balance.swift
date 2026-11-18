import Foundation

/// What's left to spend: a prepaid balance (DataForSEO's deposit, treg's wallet) or a plan allowance that
/// resets (Firecrawl's credits, Ahrefs' API units). Never spend, so it never adds into today's or this
/// month's totals.
public struct Balance: Sendable, Equatable, Codable {
    public enum Unit: Sendable, Equatable, Codable {
        /// A money balance, in its currency.
        case money(Currency)
        /// Something that isn't money, in the provider's own word: "credits", "API units".
        case units(String)
    }

    public enum Kind: String, Sendable, Equatable, Codable {
        /// Paid for up front. Runs down until it's topped up.
        case prepaid
        /// Comes with a plan and resets each period.
        case allowance
    }

    /// How much is left, in `unit`.
    public var remaining: Decimal
    public var unit: Unit
    public var kind: Kind
    /// The whole allowance, or what was deposited, when the provider says.
    public var limit: Decimal?
    /// Used so far this period, when the provider says.
    public var used: Decimal?
    /// What one unit costs in USD, for units that aren't money. Shown only as a labeled estimate.
    public var dollarsPerUnit: Decimal?
    /// When an allowance next resets, when the provider says.
    public var resetsAt: Date?

    public init(remaining: Decimal, unit: Unit, kind: Kind = .prepaid, limit: Decimal? = nil, used: Decimal? = nil,
                dollarsPerUnit: Decimal? = nil, resetsAt: Date? = nil) {
        self.remaining = remaining
        self.unit = unit
        self.kind = kind
        self.limit = limit
        self.used = used
        self.dollarsPerUnit = dollarsPerUnit
        self.resetsAt = resetsAt
    }

    /// A balance in dollars.
    public static func usd(_ remaining: Decimal, kind: Kind = .prepaid, limit: Decimal? = nil,
                           used: Decimal? = nil, resetsAt: Date? = nil) -> Balance {
        Balance(remaining: remaining, unit: .money(.usd), kind: kind, limit: limit, used: used, resetsAt: resetsAt)
    }

    /// The dollar value of a balance in units, when a rate is known. Nil for money balances (already money)
    /// and for units with no rate.
    public var estimatedDollars: Money? {
        guard case .units = unit, let dollarsPerUnit else { return nil }
        return Money(remaining * dollarsPerUnit)
    }
}

/// How balances read: "$12.40", "8,200 credits", "About $82.00 at $0.01 a credit".
public enum BalanceText {
    /// "$12.40" or "8,200 credits".
    public static func amount(_ value: Decimal, _ unit: Balance.Unit) -> String {
        switch unit {
        case .money(let currency): MoneyText.string(Money(value, currency))
        case .units(let name): "\(number(value)) \(name)"
        }
    }

    /// The figure itself: "$12.40 left", "8,200 of 10,000 credits left".
    public static func remaining(_ balance: Balance) -> String {
        if let limit = balance.limit, case .units(let name) = balance.unit {
            return "\(number(balance.remaining)) of \(number(limit)) \(name) left"
        }
        return amount(balance.remaining, balance.unit) + " left"
    }

    /// The details under the figure, each a short sentence. Empty when there's nothing more to say.
    public static func details(_ balance: Balance, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        var lines: [String] = []
        if let limit = balance.limit, case .money = balance.unit {
            let word = balance.kind == .prepaid ? "deposited" : "in the plan"
            lines.append("\(amount(limit, balance.unit)) \(word).")
        }
        if let used = balance.used {
            lines.append("\(amount(used, balance.unit)) used" + (balance.kind == .allowance ? " this period." : "."))
        }
        if let estimate = balance.estimatedDollars, let rate = balance.dollarsPerUnit,
           case .units(let name) = balance.unit {
            lines.append("About \(MoneyText.string(estimate)) at \(rateText(rate)) a \(singular(name)) (estimate).")
        }
        if let reset = balance.resetsAt {
            lines.append("Resets \(SpendText.time(reset, now: now, calendar: calendar)).")
        } else if balance.kind == .prepaid {
            lines.append("Prepaid: it doesn't reset. Top it up on the provider's site.")
        }
        return lines
    }

    /// "1,234", "12.5", "0.25". Up to two decimals, no trailing zeros.
    public static func number(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let negative = parts[0].hasPrefix("-")
        let digits = negative ? String(parts[0].dropFirst()) : String(parts[0])
        var grouped = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        let whole = (negative ? "-" : "") + String(grouped.reversed())
        return parts.count > 1 ? whole + "." + parts[1] : whole
    }

    /// "$0.01", or more digits for rates under a cent ("$0.0004").
    static func rateText(_ rate: Decimal) -> String {
        if rate >= Decimal(string: "0.01")! { return MoneyText.string(Money(rate)) }
        return "$" + NSDecimalNumber(decimal: rate).stringValue
    }

    /// "credits" to "credit", "API units" to "API unit". Leaves other words alone.
    static func singular(_ name: String) -> String {
        name.hasSuffix("s") ? String(name.dropLast()) : name
    }
}
