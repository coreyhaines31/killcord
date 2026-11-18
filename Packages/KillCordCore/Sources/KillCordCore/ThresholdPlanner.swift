import Foundation

/// Spend amounts that should send a notification: daily and monthly, per connection, per provider (all of
/// its connections together), and for the total. In USD; amounts in other currencies are never compared
/// against them.
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

    /// Keyed by `ConnectionRecord.id`.
    public var perConnection: [UUID: Limits]
    /// Across every connection of the provider.
    public var providerTotals: [ProviderID: Limits]
    public var total: Limits
    /// Kill Cord 0.1.2 kept one set of limits per provider. Read only so `migrateLegacy` can move them.
    public private(set) var legacyPerProvider: [ProviderID: Limits]

    public init(perConnection: [UUID: Limits] = [:], providerTotals: [ProviderID: Limits] = [:],
                total: Limits = Limits()) {
        self.perConnection = perConnection
        self.providerTotals = providerTotals
        self.total = total
        legacyPerProvider = [:]
    }

    private enum CodingKeys: String, CodingKey {
        case perConnection, providerTotals, total
        case legacyPerProvider = "perProvider"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        perConnection = try container.decodeIfPresent([UUID: Limits].self, forKey: .perConnection) ?? [:]
        providerTotals = try container.decodeIfPresent([ProviderID: Limits].self, forKey: .providerTotals) ?? [:]
        total = try container.decodeIfPresent(Limits.self, forKey: .total) ?? Limits()
        legacyPerProvider = try container.decodeIfPresent([ProviderID: Limits].self, forKey: .legacyPerProvider) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(perConnection, forKey: .perConnection)
        try container.encode(providerTotals, forKey: .providerTotals)
        try container.encode(total, forKey: .total)
    }

    /// Moves 0.1.2's per-provider limits onto the provider's one connection. A provider with no connection
    /// (or, which 0.1.2 couldn't have, more than one) gets them as its provider total, which is the same
    /// limit. Returns whether anything moved.
    @discardableResult
    public mutating func migrateLegacy(_ registry: ConnectionRegistry) -> Bool {
        guard !legacyPerProvider.isEmpty else { return false }
        for (provider, limits) in legacyPerProvider where !limits.isEmpty {
            let records = registry.records(for: provider)
            if records.count == 1, perConnection[records[0].id] == nil {
                perConnection[records[0].id] = limits
            } else if providerTotals[provider] == nil {
                providerTotals[provider] = limits
            }
        }
        legacyPerProvider = [:]
        return true
    }

    public var isEmpty: Bool {
        total.isEmpty && perConnection.values.allSatisfy(\.isEmpty) && providerTotals.values.allSatisfy(\.isEmpty)
    }
}

/// Decides which threshold notifications to send after a refresh: each threshold fires at most once per
/// period (day or month, on the provider's billing clock). Pure; the app posts what it returns and saves the
/// state.
public struct ThresholdPlanner: Sendable {
    public struct State: Sendable, Equatable, Codable {
        /// "<connection uuid>|day|2026-11-15|50" for a connection, "anthropic|day|…" for a provider total,
        /// "total|month|2026-11|500" for everything.
        public var fired: Set<String>

        public init(fired: Set<String> = []) {
            self.fired = fired
        }

        /// 0.1.2 keyed a provider's alerts by provider. Moves those to the provider's one connection, the
        /// same way `SpendThresholds.migrateLegacy` moves the limits, so nothing fires twice on upgrade day.
        public func migrated(_ registry: ConnectionRegistry) -> State {
            State(fired: Set(fired.map { key in
                let parts = key.split(separator: "|", maxSplits: 1)
                guard parts.count == 2, let provider = ProviderID(rawValue: String(parts[0])) else { return key }
                let records = registry.records(for: provider)
                guard records.count == 1 else { return key }
                return records[0].id.uuidString + "|" + parts[1]
            }))
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

    // Keep period checks with the state they accumulate.
    // swiftlint:disable:next function_body_length
    public func plan(states: [ProviderState], names: [UUID: String] = [:], thresholds: SpendThresholds,
                     state: State, now: Date) -> ([Alert], State) {
        var alerts: [Alert] = []
        var fired = state.fired
        var totalToday = Decimal(0)
        var totalMonth = Decimal(0)
        var estimate = false

        // swiftlint:disable:next function_parameter_count
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

        for provider in ProviderID.allCases {
            let members = states.filter { $0.provider == provider && $0.snapshot != nil }
            guard !members.isEmpty else { continue }
            let window = BillingWindow(now: now, timeZone: provider.info.billingTimeZone)
            var providerToday = Decimal(0)
            var providerMonth = Decimal(0)
            var providerEstimate = false
            var sawToday = false
            var sawMonth = false
            for member in members {
                guard let snapshot = member.snapshot else { continue }
                let readWindow = BillingWindow(now: snapshot.fetchedAt, timeZone: window.timeZone)
                let limits = thresholds.perConnection[member.connectionID] ?? .init()
                let name = names[member.connectionID] ?? provider.info.name
                let prefix = member.connectionID.uuidString
                if let today = snapshot.today, today.currency == .usd, readWindow.dayKey == window.dayKey {
                    providerToday += today.amount
                    sawToday = true
                    providerEstimate = providerEstimate || snapshot.isEstimate
                    check(name, idPrefix: prefix, period: .day, periodKey: window.dayKey, amount: today.amount,
                          limit: limits.daily, isEstimate: snapshot.isEstimate, checkedAt: snapshot.fetchedAt)
                }
                if let month = snapshot.month, month.currency == .usd, readWindow.monthKey == window.monthKey {
                    providerMonth += month.amount
                    sawMonth = true
                    providerEstimate = providerEstimate || snapshot.isEstimate
                    check(name, idPrefix: prefix, period: .month, periodKey: window.monthKey, amount: month.amount,
                          limit: limits.monthly, isEstimate: snapshot.isEstimate, checkedAt: snapshot.fetchedAt)
                }
            }
            let limits = thresholds.providerTotals[provider] ?? .init()
            let name = "All \(provider.info.name) accounts"
            if sawToday {
                check(name, idPrefix: provider.rawValue, period: .day, periodKey: window.dayKey, amount: providerToday,
                      limit: limits.daily, isEstimate: providerEstimate, checkedAt: nil)
            }
            if sawMonth {
                check(name, idPrefix: provider.rawValue, period: .month, periodKey: window.monthKey,
                      amount: providerMonth, limit: limits.monthly, isEstimate: providerEstimate, checkedAt: nil)
            }
            totalToday += providerToday
            totalMonth += providerMonth
            estimate = estimate || providerEstimate
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
