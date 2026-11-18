import Foundation

/// What Kill Cord last knew about one connection. Saved between launches (spend numbers only, never keys),
/// so the panel can show the last reading, clearly marked as not live.
public struct ProviderState: Sendable, Equatable, Codable {
    public let provider: ProviderID
    /// The `ConnectionRecord` this reading belongs to.
    public let connectionID: UUID
    public var snapshot: SpendSnapshot?
    public var lastAttempt: Date?
    public var lastError: SpendError?

    public init(provider: ProviderID, connectionID: UUID, snapshot: SpendSnapshot? = nil, lastAttempt: Date? = nil,
                lastError: SpendError? = nil) {
        self.provider = provider
        self.connectionID = connectionID
        self.snapshot = snapshot
        self.lastAttempt = lastAttempt
        self.lastError = lastError
    }

    public var lastSuccess: Date? { snapshot?.fetchedAt }

    public mutating func record(_ snapshot: SpendSnapshot) {
        self.snapshot = snapshot
        lastAttempt = snapshot.fetchedAt
        lastError = nil
    }

    public mutating func record(_ error: SpendError, at date: Date) {
        lastAttempt = date
        lastError = error
    }
}

/// The facts freshness depends on, gathered by the app.
public struct FreshnessContext: Sendable, Equatable {
    public var now: Date
    /// When this run of the app started. Readings from before it are from a previous run.
    public var launchedAt: Date
    /// The last time the Mac woke from sleep in this run, if it has.
    public var lastWake: Date?
    public var isAsleep: Bool
    public var isOnline: Bool
    /// The refresh interval in use.
    public var interval: TimeInterval

    public init(now: Date, launchedAt: Date, lastWake: Date? = nil, isAsleep: Bool = false, isOnline: Bool = true,
                interval: TimeInterval) {
        self.now = now
        self.launchedAt = launchedAt
        self.lastWake = lastWake
        self.isAsleep = isAsleep
        self.isOnline = isOnline
        self.interval = interval
    }
}

/// Whether a provider's number is current. The free app polls only while the Mac is awake, so anything read
/// before the Mac last slept is stale until the next successful check. Never implies overnight coverage.
public enum Freshness: Equatable, Sendable {
    case neverChecked
    case live(checkedAt: Date)
    case stale(checkedAt: Date, reason: StaleReason)

    public enum StaleReason: Equatable, Sendable {
        /// The Mac slept since the last check.
        case slept
        /// Kill Cord wasn't running: this reading is from an earlier session.
        case notRunning
        case offline
        /// The latest check failed.
        case failed
        /// No check for longer than the refresh interval allows.
        case overdue
    }

    public static func of(_ state: ProviderState, context: FreshnessContext) -> Freshness {
        guard let checked = state.lastSuccess else { return .neverChecked }
        let refreshInterval = max(context.interval, state.provider.info.minimumRefreshInterval)
        if context.isAsleep { return .stale(checkedAt: checked, reason: .slept) }
        if let wake = context.lastWake, checked < wake { return .stale(checkedAt: checked, reason: .slept) }
        if checked < context.launchedAt { return .stale(checkedAt: checked, reason: .notRunning) }
        if !context.isOnline { return .stale(checkedAt: checked, reason: .offline) }
        if let attempt = state.lastAttempt, attempt > checked, state.lastError != nil {
            return .stale(checkedAt: checked, reason: .failed)
        }
        // Two missed intervals (plus slack for a slow request) and it's no longer live.
        if context.now.timeIntervalSince(checked) > 2 * refreshInterval + 120 {
            return .stale(checkedAt: checked, reason: .overdue)
        }
        return .live(checkedAt: checked)
    }

    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    public var checkedAt: Date? {
        switch self {
        case .neverChecked: nil
        case .live(let at), .stale(let at, _): at
        }
    }
}
