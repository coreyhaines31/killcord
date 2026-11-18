import Foundation

/// A paid service with no API (Truelist, Gojiberry, Resend, Postmark): what the person typed in about its
/// plan. Never read from the service, never live, never added into spend totals. Kill Cord only rolls the
/// renewal date forward and reminds before it.
public struct ManualPlan: Sendable, Equatable, Codable {
    public enum Period: String, Sendable, Codable, CaseIterable {
        case monthly = "Monthly"
        case yearly = "Yearly"
    }

    public var plan: String?
    public var price: Money?
    public var period: Period
    /// The next renewal on or after the day it was worked out.
    public var renewsOn: Date
    /// Credits or other units the plan includes each period, as the person entered them.
    public var allowance: Decimal?
    public var allowanceUnit: String?
    /// Days before renewal to remind. Nil for no reminder.
    public var remindDaysBefore: Int?

    public init(plan: String? = nil, price: Money? = nil, period: Period = .monthly, renewsOn: Date,
                allowance: Decimal? = nil, allowanceUnit: String? = nil, remindDaysBefore: Int? = 3) {
        self.plan = plan
        self.price = price
        self.period = period
        self.renewsOn = renewsOn
        self.allowance = allowance
        self.allowanceUnit = allowanceUnit
        self.remindDaysBefore = remindDaysBefore
    }

    public static let remindChoices = ["3", "1", "7", "None"]
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Reads and checks what was typed. Throws `.requiresSetup` with what to fix.
    public init(_ credentials: ProviderCredentials, now: Date) throws {
        guard let dateText = credentials["renewsOn"], let first = Self.day(dateText) else {
            throw SpendError.requiresSetup("enter the next renewal date as 2026-12-03.")
        }
        var price: Money?
        if let text = credentials["price"] {
            guard let amount = Money.decimal(text.replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")), amount >= 0 else {
                throw SpendError.requiresSetup("enter the price as a number, like 49 or 49.00.")
            }
            price = Money(amount)
        }
        var allowance: Decimal?
        if let text = credentials["allowance"] {
            guard let value = Money.decimal(text.replacingOccurrences(of: ",", with: "")), value >= 0 else {
                throw SpendError.requiresSetup("enter the included credits as a number.")
            }
            allowance = value
        }
        let period = Period(rawValue: credentials["period"] ?? "") ?? .monthly
        self.init(plan: credentials["plan"], price: price, period: period,
                  renewsOn: Self.next(first, period: period, onOrAfter: now), allowance: allowance,
                  allowanceUnit: allowance == nil ? nil : (credentials["allowanceUnit"] ?? "credits"),
                  remindDaysBefore: Int(credentials["remindDays"] ?? Self.remindChoices[0]))
    }

    /// "2026-12-03" as midnight UTC.
    static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return formatter.date(from: text)
    }

    /// The renewal on or after today's date, stepping a month or a year at a time from the one entered.
    /// Steps from the entered day each time, so a plan that renews on the 31st stays at month end.
    static func next(_ start: Date, period: Period, onOrAfter now: Date) -> Date {
        let today = localDay(now)
        var steps = 0
        var date = start
        while date < today, steps < 1200 {
            steps += 1
            let step = period == .monthly ? DateComponents(month: steps) : DateComponents(year: steps)
            date = utc.date(byAdding: step, to: start) ?? date
        }
        return date
    }

    /// The person's calendar day for `now`, as the midnight-UTC date the plan's dates are kept in. A renewal
    /// on Nov 18 is "today" when it's Nov 18 on the Mac's clock, whatever the hour in UTC.
    static func localDay(_ now: Date, in timeZone: TimeZone = .current) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: now)
        return utc.date(from: parts) ?? utc.startOfDay(for: now)
    }

    /// Whole days from the person's today until the renewal.
    public func daysUntilRenewal(now: Date) -> Int {
        let today = Self.localDay(now)
        return Self.utc.dateComponents([.day], from: today, to: renewsOn).day ?? 0
    }
}

/// How manual plans read.
public enum ManualText {
    /// "$49.00 a month", or nil with no price.
    public static func price(_ plan: ManualPlan) -> String? {
        plan.price.map { MoneyText.string($0) + (plan.period == .monthly ? " a month" : " a year") }
    }

    /// "Renews Dec 3", "Renews today", "Renews tomorrow".
    public static func renewal(_ plan: ManualPlan, now: Date) -> String {
        switch plan.daysUntilRenewal(now: now) {
        case 0: "Renews today"
        case 1: "Renews tomorrow"
        default: "Renews " + renewalDay(plan, now: now)
        }
    }

    /// "Dec 3", "Today", "Tomorrow".
    public static func renewalDay(_ plan: ManualPlan, now: Date) -> String {
        switch plan.daysUntilRenewal(now: now) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "MMM d"
            return formatter.string(from: plan.renewsOn)
        }
    }

    /// "10,000 credits a month included".
    public static func allowance(_ plan: ManualPlan) -> String? {
        guard let allowance = plan.allowance else { return nil }
        let per = plan.period == .monthly ? "a month" : "a year"
        return "\(BalanceText.number(allowance)) \(plan.allowanceUnit ?? "credits") \(per) included"
    }

    /// Everything known, in one line for the sidebar: "Starter · $49.00 a month · Renews Dec 3".
    public static func summary(_ plan: ManualPlan, now: Date) -> String {
        [plan.plan, price(plan), renewal(plan, now: now)].compactMap { $0 }.joined(separator: " · ")
    }

    public static let notLive = "Not live: entered by you"
}
