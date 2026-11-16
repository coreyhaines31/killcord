import Foundation

/// Spend amounts that should send a notification: daily and monthly, per provider and for the total. In USD;
/// amounts in other currencies are never compared against them.
public struct SpendThresholds: Sendable, Equatable, Codable {
    public struct Limits: Sendable, Equatable, Codable {
        public var daily: Decimal?
        public var monthly: Decimal?

        public init(daily: Decimal? = nil, monthly: Decimal? = nil) {
            self.daily = daily
            self.monthly = monthly
        }

        public var isEmpty: Bool { daily == nil && monthly == nil }
    }

    public var perProvider: [ProviderID: Limits]
    public var total: Limits

    public init(perProvider: [ProviderID: Limits] = [:], total: Limits = Limits()) {
        self.perProvider = perProvider
        self.total = total
    }
}

/// Decides which threshold notifications to send after a refresh: each threshold fires at most once per
/// period (day or month, on the provider's billing clock). Pure; the app posts what it returns and saves the
/// state.
public struct ThresholdPlanner: Sendable {
    public struct State: Sendable, Equatable, Codable {
        /// "anthropic|day|2026-11-15|50", "total|month|2026-11|500"
        public var fired: Set<String>

        public init(fired: Set<String> = []) {
            self.fired = fired
        }
    }

    public struct Alert: Sendable, Equatable {
        public let id: String
        public let title: String
        public let body: String
    }

    public init() {}

    private enum Period {
        case day
        case month

        var key: String { self == .day ? "day" : "month" }
        var word: String { self == .day ? "today" : "this month" }
        var adjective: String { self == .day ? "daily" : "monthly" }
    }

    public func plan(states: [ProviderState], thresholds: SpendThresholds, state: State,
                     now: Date) -> ([Alert], State) {
        var alerts: [Alert] = []
        var fired = state.fired
        var totalToday = Decimal(0)
        var totalMonth = Decimal(0)
        var estimate = false

        func check(_ name: String, idPrefix: String, period: Period, periodKey: String, amount: Decimal,
                   limit: Decimal?, isEstimate: Bool, checkedAt: Date?) {
            guard let limit, limit > 0 else { return }
            let id = "\(idPrefix)|\(period.key)|\(periodKey)|\(limit)"
            guard amount >= limit, !fired.contains(id) else { return }
            fired.insert(id)
            let spent = MoneyText.string(Money(amount)) + (isEstimate ? " (estimate)" : "")
            var body = "That's past your \(MoneyText.string(Money(limit))) \(period.adjective) alert."
            if let checkedAt { body += " Last checked \(SpendText.time(checkedAt, now: now))." }
            alerts.append(Alert(id: id, title: "\(name) spent \(spent) \(period.word)", body: body))
        }

        for providerState in states.sorted(by: { $0.provider < $1.provider }) {
            guard let snapshot = providerState.snapshot else { continue }
            let provider = providerState.provider
            let window = BillingWindow(now: now, timeZone: provider.info.billingTimeZone)
            let readWindow = BillingWindow(now: snapshot.fetchedAt, timeZone: window.timeZone)
            let limits = thresholds.perProvider[provider] ?? .init()
            if let today = snapshot.today, today.currency == .usd, readWindow.dayKey == window.dayKey {
                totalToday += today.amount
                estimate = estimate || snapshot.isEstimate
                check(provider.info.name, idPrefix: provider.rawValue, period: .day, periodKey: window.dayKey,
                      amount: today.amount, limit: limits.daily, isEstimate: snapshot.isEstimate,
                      checkedAt: snapshot.fetchedAt)
            }
            if let month = snapshot.month, month.currency == .usd, readWindow.monthKey == window.monthKey {
                totalMonth += month.amount
                estimate = estimate || snapshot.isEstimate
                check(provider.info.name, idPrefix: provider.rawValue, period: .month, periodKey: window.monthKey,
                      amount: month.amount, limit: limits.monthly, isEstimate: snapshot.isEstimate,
                      checkedAt: snapshot.fetchedAt)
            }
        }
        let utc = BillingWindow(now: now, timeZone: TimeZone(identifier: "UTC")!)
        check("All providers", idPrefix: "total", period: .day, periodKey: utc.dayKey, amount: totalToday,
              limit: thresholds.total.daily, isEstimate: estimate, checkedAt: nil)
        check("All providers", idPrefix: "total", period: .month, periodKey: utc.monthKey, amount: totalMonth,
              limit: thresholds.total.monthly, isEstimate: estimate, checkedAt: nil)
        // Forget periods that are over, so the saved state stays small. Keep keys for the current periods
        // even when the provider wasn't read this time (an error shouldn't let an alert fire twice).
        let livePeriods = Set(ProviderID.allCases.flatMap { provider -> [String] in
            let window = BillingWindow(now: now, timeZone: provider.info.billingTimeZone)
            return [window.dayKey, window.monthKey]
        } + [utc.dayKey, utc.monthKey])
        fired = fired.filter { key in
            let parts = key.split(separator: "|")
            return parts.count == 4 && livePeriods.contains(String(parts[2]))
        }
        return (alerts, State(fired: fired))
    }
}
