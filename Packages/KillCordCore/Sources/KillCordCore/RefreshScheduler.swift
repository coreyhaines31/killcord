import Foundation

/// Decides when each provider is asked next. Pure: the app calls it on a timer, on sleep and wake, and when
/// keys change, then asks the providers it returns.
///
/// - Polls every `interval`, never faster than a provider's own minimum.
/// - Backs off on transient failures (doubling from `baseBackoff` up to `maxBackoff`), and waits at least as
///   long as a rate limit's Retry-After.
/// - Stops asking a provider after a failure only the person can fix (rejected key, missing permission),
///   until its key changes or they press Refresh.
/// - Asks nothing while the Mac sleeps, and asks everyone shortly after it wakes.
public struct RefreshScheduler: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        /// Nil while suspended or in flight.
        public var nextDue: Date?
        public var failures: Int = 0
        public var inFlight = false
        public var suspended = false
    }

    public static let intervalChoices: [TimeInterval] = [5 * 60, 15 * 60, 30 * 60, 60 * 60]
    public static let defaultInterval: TimeInterval = 15 * 60

    public var interval: TimeInterval
    public var baseBackoff: TimeInterval
    public var maxBackoff: TimeInterval
    /// After wake, the network usually needs a few seconds to come back.
    public var wakeDelay: TimeInterval
    public private(set) var entries: [ProviderID: Entry] = [:]
    public private(set) var isAsleep = false

    public init(interval: TimeInterval = RefreshScheduler.defaultInterval, baseBackoff: TimeInterval = 60,
                maxBackoff: TimeInterval = 60 * 60, wakeDelay: TimeInterval = 10) {
        self.interval = interval
        self.baseBackoff = baseBackoff
        self.maxBackoff = maxBackoff
        self.wakeDelay = wakeDelay
    }

    public func interval(for provider: ProviderID) -> TimeInterval {
        max(interval, provider.info.minimumRefreshInterval)
    }

    /// Starts tracking a provider, due right away. Also used when its key changes.
    public mutating func add(_ provider: ProviderID, now: Date) {
        entries[provider] = Entry(nextDue: now)
    }

    public mutating func remove(_ provider: ProviderID) {
        entries[provider] = nil
    }

    /// Providers to ask now. Marks them in flight. Nothing while asleep.
    public mutating func takeDue(now: Date) -> [ProviderID] {
        guard !isAsleep else { return [] }
        let due = entries.filter { entry in
            !entry.value.inFlight && !entry.value.suspended && (entry.value.nextDue.map { $0 <= now } ?? false)
        }.keys.sorted()
        for provider in due {
            entries[provider]?.inFlight = true
            entries[provider]?.nextDue = nil
        }
        return due
    }

    public mutating func succeeded(_ provider: ProviderID, now: Date) {
        guard entries[provider] != nil else { return }
        entries[provider] = Entry(nextDue: now.addingTimeInterval(interval(for: provider)))
    }

    public mutating func failed(_ provider: ProviderID, error: SpendError, now: Date) {
        guard var entry = entries[provider] else { return }
        entry.inFlight = false
        entry.failures += 1
        if error.isTransient {
            var delay = min(maxBackoff, baseBackoff * pow(2, Double(min(entry.failures - 1, 20))))
            if case .rateLimited(let retryAfter) = error, let retryAfter {
                delay = max(delay, retryAfter)
            }
            entry.nextDue = now.addingTimeInterval(delay)
        } else {
            entry.suspended = true
            entry.nextDue = nil
        }
        entries[provider] = entry
    }

    /// Refresh pressed: everything not in flight is due now, suspended ones included. A provider still
    /// inside a rate limit's wait keeps waiting.
    public mutating func refreshAll(now: Date) {
        for (provider, entry) in entries where !entry.inFlight {
            if entry.failures > 0, !entry.suspended, let due = entry.nextDue, due > now { continue }
            entries[provider]?.suspended = false
            entries[provider]?.nextDue = now
        }
    }

    public mutating func sleep() {
        isAsleep = true
    }

    /// Everyone not suspended is due shortly after waking. Requests that were in flight when the Mac slept
    /// are treated as lost.
    public mutating func wake(now: Date) {
        isAsleep = false
        for (provider, entry) in entries where !entry.suspended {
            entries[provider]?.inFlight = false
            // Not before the network is back, and not later than a rate limit's wait requires.
            let soon = now.addingTimeInterval(wakeDelay)
            entries[provider]?.nextDue = max(soon, entry.failures > 0 ? (entry.nextDue ?? soon) : soon)
        }
    }

    public mutating func setInterval(_ newInterval: TimeInterval, now: Date) {
        interval = newInterval
        for (provider, entry) in entries where entry.failures == 0 && !entry.inFlight && !entry.suspended {
            let cap = now.addingTimeInterval(interval(for: provider))
            entries[provider]?.nextDue = min(entry.nextDue ?? cap, cap)
        }
    }

    /// When the app's timer should next fire. Nil when nothing is scheduled.
    public var nextDue: Date? {
        guard !isAsleep else { return nil }
        return entries.values.filter { !$0.suspended && !$0.inFlight }.compactMap(\.nextDue).min()
    }
}
