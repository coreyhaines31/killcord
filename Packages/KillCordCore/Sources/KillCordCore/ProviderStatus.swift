import Foundation

/// The four lights Settings and the panel use. The app maps them to PanelKit's status LEDs.
public enum SignalLight: String, Sendable, Equatable {
    case go
    case caution
    case stop
    case off
}

/// One provider's state in a word and a line, for the Settings sidebar and the detail header. Built only
/// from what Kill Cord read: no number appears unless the provider reported it.
public struct ProviderStatus: Sendable, Equatable {
    public let light: SignalLight
    /// The word beside the LED in the detail header: "Connected", "Not live", "Key rejected".
    public let label: String
    /// The sidebar line: "Connected · $18.42 today", "Checked 3h ago, not live".
    public let line: String

    public init(light: SignalLight, label: String, line: String) {
        self.light = light
        self.label = label
        self.line = line
    }

    public static func of(_ provider: ProviderID, isConnected: Bool, state: ProviderState?, freshness: Freshness,
                          isChecking: Bool = false, now: Date = Date()) -> ProviderStatus {
        let info = provider.info
        guard info.connects else { return ProviderStatus(light: .off, label: "Caps only", line: "Caps only") }
        if isChecking, state?.snapshot == nil {
            return ProviderStatus(light: .caution, label: "Checking", line: "Checking…")
        }
        guard isConnected else {
            return ProviderStatus(light: .off, label: "Not connected", line: "Not connected")
        }
        if let error = state?.lastError, !error.isTransient {
            return ProviderStatus(light: .stop, label: error.shortLabel, line: error.shortLabel)
        }
        switch freshness {
        case .neverChecked:
            if let error = state?.lastError {
                return ProviderStatus(light: .caution, label: error.shortLabel, line: error.shortLabel)
            }
            return ProviderStatus(light: .caution, label: "Connected", line: "Connected, not read yet")
        case .stale(let at, _):
            return ProviderStatus(light: .caution, label: "Not live",
                                  line: "Checked \(SpendText.ago(at, now: now)), not live")
        case .live:
            let reading = state?.snapshot.flatMap(headline)
            return ProviderStatus(light: .go, label: "Connected",
                                  line: reading.map { "Connected · \($0)" } ?? "Connected")
        }
    }

    /// The single most useful number: today's spend, else this month's, else the first usage figure.
    static func headline(_ snapshot: SpendSnapshot) -> String? {
        let estimate = snapshot.isEstimate ? " (estimate)" : ""
        if let today = snapshot.today { return "\(MoneyText.string(today)) today\(estimate)" }
        if let month = snapshot.month {
            let period = if case .billingPeriod = snapshot.monthKind { "this period" } else { "this month" }
            return "\(MoneyText.string(month)) \(period)\(estimate)"
        }
        if let metric = snapshot.usage.first { return SpendText.usage(metric) }
        return nil
    }
}

extension SpendError {
    /// What to do about a failed connect, in one sentence. Nil when the message already says it.
    public func fix(for provider: ProviderID) -> String? {
        let info = provider.info
        switch self {
        case .notConfigured: return "Fill in every required field, then connect again."
        case .invalidKey: return "Copy the key again, or create a new one in the \(info.consoleName)."
        case .missingScope, .requiresSetup, .planNotSupported, .noUsageAPI: return nil
        case .rateLimited: return "Wait a minute, then connect again."
        case .offline: return "Check your internet connection, then connect again."
        case .network, .server, .unexpectedStatus: return "Try again in a minute."
        case .unexpectedResponse, .rejected: return "Check for a Kill Cord update in General."
        }
    }
}

extension CapAuditState.Status {
    /// The checklist light: green when the cap is on, amber when it needs a look, red when the provider is
    /// stopping spend right now, off when nothing's been done.
    public var light: SignalLight {
        switch self {
        case .verifiedOn: .go
        case .markedDone(_, let recheck): recheck ? .caution : .go
        case .verifiedOff: .caution
        case .enforced: .stop
        case .notDone, .notApplicable: .off
        }
    }

    /// A word or two beside the light.
    public var label: String {
        switch self {
        case .verifiedOn: "On, checked"
        case .markedDone(_, let recheck): recheck ? "Check again" : "Done"
        case .verifiedOff: "Off"
        case .enforced: "Stopping spend"
        case .notDone: "Not done"
        case .notApplicable: "Not needed"
        }
    }
}
