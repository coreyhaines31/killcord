import Foundation

/// The words the panel, the menu bar, and notifications use, in one place so they agree.
public enum SpendText {
    /// "11:42p" today, "Tue 9a" this week, "Nov 3" before that.
    public static func time(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let clock = "\(hour % 12 == 0 ? 12 : hour % 12)" + (minute == 0 ? "" : String(format: ":%02d", minute))
            + (hour < 12 ? "a" : "p")
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if days >= 0, days < 7 {
            formatter.dateFormat = "EEE"
            return "\(formatter.string(from: date)) \(clock)"
        }
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// "45m", "3h 7m", "2d 16h".
    public static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(max(0, Int(seconds.rounded())))s" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m" }
        return hours % 24 == 0 ? "\(hours / 24)d" : "\(hours / 24)d \(hours % 24)h"
    }

    /// "Checked 11:42p", "Last checked 11:42p, not live", "Not checked yet".
    public static func freshness(_ freshness: Freshness, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch freshness {
        case .neverChecked: return "Not checked yet"
        case .live(let at): return "Checked \(time(at, now: now, calendar: calendar))"
        case .stale(let at, _): return "Last checked \(time(at, now: now, calendar: calendar)), not live"
        }
    }

    /// Why a reading isn't live, or nil when it is.
    public static func staleReason(_ freshness: Freshness) -> String? {
        guard case .stale(_, let reason) = freshness else { return nil }
        switch reason {
        case .slept: return "Your Mac was asleep, so Kill Cord wasn't checking. It checks again shortly after wake."
        case .notRunning: return "From before Kill Cord last quit. It checks again now that it's running."
        case .offline: return "Your Mac is offline."
        case .failed: return "The latest check failed."
        case .overdue: return "No successful check for a while."
        }
    }

    /// "This month" or "Billing period from Nov 3".
    public static func monthLabel(_ kind: SpendSnapshot.MonthKind, now: Date = Date(),
                                  calendar: Calendar = .current) -> String {
        switch kind {
        case .calendarMonth: return "This month"
        case .billingPeriod(let start):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "MMM d"
            return "Billing period from \(formatter.string(from: start))"
        }
    }

    /// "$12.40", or "Not reported yet" when a provider hasn't reported the period.
    public static func amount(_ money: Money?, isEstimate: Bool = false) -> String {
        guard let money else { return "Not reported yet" }
        return MoneyText.string(money) + (isEstimate ? " (estimate)" : "")
    }

    /// "12.5 CU-hours".
    public static func usage(_ metric: UsageMetric) -> String {
        var input = metric.value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, metric.value < 10 ? 2 : 1, .plain)
        return "\(NSDecimalNumber(decimal: rounded).stringValue) \(metric.unit)"
    }

    /// The menu bar's text: compact total, with a marker when it isn't the whole, live story.
    public static func menuBar(_ summary: SpendSummary, period: MenuBarPeriod) -> String {
        let totals = period == .today ? summary.today : summary.month
        guard !summary.rows.isEmpty else { return "" }
        let usd = totals.amount(in: .usd) ?? .zero()
        var text = MoneyText.compact(usd)
        if totals.byCurrency.keys.contains(where: { $0 != .usd }) { text += "+" }
        if !summary.stale.isEmpty { text += "*" }
        return text
    }

    public enum MenuBarPeriod: String, CaseIterable, Sendable, Identifiable {
        case today
        case month

        public var id: String { rawValue }
        public var title: String { self == .today ? "Today" : "This month" }
    }
}
