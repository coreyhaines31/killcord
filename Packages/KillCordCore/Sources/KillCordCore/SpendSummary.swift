import Foundation

/// Totals across connections, with the honesty attached: which numbers are missing, stale, or estimates, so
/// the total is never shown as more complete than it is.
public struct SpendSummary: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let connectionID: UUID
        public let provider: ProviderID
        public let name: String
        public let today: Money?
        public let month: Money?
        public let freshness: Freshness
        public let error: SpendError?
        public var id: UUID { connectionID }
    }

    /// One provider's connections, with a subtotal of the numbers that count for today and this month.
    public struct Group: Equatable, Sendable, Identifiable {
        public let provider: ProviderID
        public let rows: [Row]
        public let today: MoneyTotals
        public let month: MoneyTotals
        public var id: ProviderID { provider }
    }

    public let rows: [Row]
    public let groups: [Group]
    public let today: MoneyTotals
    public let month: MoneyTotals
    /// Connected money connections whose today isn't in `today` (not reported yet, or never read).
    public let missingToday: [UUID]
    /// Connected money connections whose month isn't in `month`.
    public let missingMonth: [UUID]
    /// Connections included in the totals with a reading that isn't live.
    public let stale: [UUID]
    public let failing: [UUID]
    public let hasEstimates: Bool

    /// - Parameters:
    ///   - states: one per connection. Rows follow provider order, then the order given here.
    ///   - names: connection id to its name. A connection with none shows its provider's name.
    public init(states: [ProviderState], names: [UUID: String] = [:], context: FreshnessContext) {
        var rows: [Row] = []
        var today = MoneyTotals()
        var month = MoneyTotals()
        var missingToday: [UUID] = []
        var missingMonth: [UUID] = []
        var stale: [UUID] = []
        var failing: [UUID] = []
        var hasEstimates = false
        let ordered = states.enumerated().sorted { ($0.element.provider, $0.offset) < ($1.element.provider, $1.offset) }
            .map(\.element)
        for state in ordered {
            let id = state.connectionID
            let freshness = Freshness.of(state, context: context)
            let snapshot = state.snapshot
            // Only numbers for the current day and month count toward today's and this month's totals.
            let window = BillingWindow(now: context.now, timeZone: state.provider.info.billingTimeZone)
            let readWindow = snapshot.map { BillingWindow(now: $0.fetchedAt, timeZone: window.timeZone) }
            let todayValue = readWindow?.dayKey == window.dayKey ? snapshot?.today : nil
            let monthValue = readWindow?.monthKey == window.monthKey ? snapshot?.month : nil
            rows.append(Row(connectionID: id, provider: state.provider, name: names[id] ?? state.provider.info.name,
                            today: todayValue, month: monthValue, freshness: freshness, error: state.lastError))
            // Balances never count: they're what's left, not what was spent.
            let capability = state.provider.info.capability
            if capability.countsToday {
                if let todayValue { today.add(todayValue) } else { missingToday.append(id) }
            }
            if capability.countsMonth {
                if let monthValue { month.add(monthValue) } else { missingMonth.append(id) }
            }
            if capability.showsMoney {
                let counted = (capability.countsToday && todayValue != nil) || (capability.countsMonth && monthValue != nil)
                if counted, !freshness.isLive { stale.append(id) }
                if snapshot?.isEstimate == true { hasEstimates = true }
            }
            if state.lastError != nil { failing.append(id) }
        }
        self.rows = rows
        groups = Self.groups(rows)
        self.today = today
        self.month = month
        self.missingToday = missingToday
        self.missingMonth = missingMonth
        self.stale = stale
        self.failing = failing
        self.hasEstimates = hasEstimates
    }

    private static func groups(_ rows: [Row]) -> [Group] {
        ProviderID.allCases.compactMap { provider in
            let members = rows.filter { $0.provider == provider }
            guard !members.isEmpty else { return nil }
            var today = MoneyTotals()
            var month = MoneyTotals()
            for row in members {
                if let value = row.today { today.add(value) }
                if let value = row.month { month.add(value) }
            }
            return Group(provider: provider, rows: members, today: today, month: month)
        }
    }

    /// True when every money connection is in the totals with a live reading.
    public var isComplete: Bool {
        missingToday.isEmpty && missingMonth.isEmpty && stale.isEmpty
    }

    /// The names of these connections, for "Today leaves out Anthropic 2".
    public func names(_ ids: [UUID]) -> [String] {
        ids.compactMap { id in rows.first { $0.connectionID == id }?.name }
    }
}
