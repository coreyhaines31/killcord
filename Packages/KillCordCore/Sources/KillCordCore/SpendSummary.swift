import Foundation

/// Totals across providers, with the honesty attached: which numbers are missing, stale, or estimates, so
/// the total is never shown as more complete than it is.
public struct SpendSummary: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let provider: ProviderID
        public let today: Money?
        public let month: Money?
        public let freshness: Freshness
        public let error: SpendError?
        public var id: ProviderID { provider }
    }

    public let rows: [Row]
    public let today: MoneyTotals
    public let month: MoneyTotals
    /// Connected providers whose today isn't in `today` (not reported yet, or never read).
    public let missingToday: [ProviderID]
    /// Connected providers whose month isn't in `month`.
    public let missingMonth: [ProviderID]
    /// Providers included in the totals with a reading that isn't live.
    public let stale: [ProviderID]
    public let failing: [ProviderID]
    public let hasEstimates: Bool

    /// - Parameter states: one per connected provider.
    public init(states: [ProviderState], context: FreshnessContext) {
        var rows: [Row] = []
        var today = MoneyTotals()
        var month = MoneyTotals()
        var missingToday: [ProviderID] = []
        var missingMonth: [ProviderID] = []
        var stale: [ProviderID] = []
        var failing: [ProviderID] = []
        var hasEstimates = false
        for state in states.sorted(by: { $0.provider < $1.provider }) {
            let freshness = Freshness.of(state, context: context)
            let snapshot = state.snapshot
            // Only numbers for the current day and month count toward today's and this month's totals.
            let window = BillingWindow(now: context.now, timeZone: state.provider.info.billingTimeZone)
            let readWindow = snapshot.map { BillingWindow(now: $0.fetchedAt, timeZone: window.timeZone) }
            let todayValue = readWindow?.dayKey == window.dayKey ? snapshot?.today : nil
            let monthValue = readWindow?.monthKey == window.monthKey ? snapshot?.month : nil
            rows.append(Row(provider: state.provider, today: todayValue, month: monthValue, freshness: freshness,
                            error: state.lastError))
            if state.provider.info.capability.showsMoney {
                if let todayValue { today.add(todayValue) } else { missingToday.append(state.provider) }
                if let monthValue { month.add(monthValue) } else { missingMonth.append(state.provider) }
                if todayValue != nil || monthValue != nil, !freshness.isLive { stale.append(state.provider) }
                if snapshot?.isEstimate == true { hasEstimates = true }
            }
            if state.lastError != nil { failing.append(state.provider) }
        }
        self.rows = rows
        self.today = today
        self.month = month
        self.missingToday = missingToday
        self.missingMonth = missingMonth
        self.stale = stale
        self.failing = failing
        self.hasEstimates = hasEstimates
    }

    /// True when every money provider is in the totals with a live reading.
    public var isComplete: Bool {
        missingToday.isEmpty && missingMonth.isEmpty && stale.isEmpty
    }
}
