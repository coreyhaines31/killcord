import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything that can go wrong reading spend, in terms a person can act on. Messages are built only from
/// fixed text and numbers. No case carries a response body, a header, or anything typed into a key field,
/// so no message can contain a secret.
public enum SpendError: Error, Equatable, Sendable, Codable {
    /// No key saved, or a required field is empty.
    case notConfigured
    /// The provider rejected the key (HTTP 401, or a token that couldn't be exchanged).
    case invalidKey
    /// The key works but can't read billing. The hint names the permission to add.
    case missingScope(hint: String)
    /// Too many requests. Retry after this many seconds, when the provider says.
    case rateLimited(retryAfter: TimeInterval?)
    /// The provider has no API for spend.
    case noUsageAPI
    /// Something has to be set up on the provider's side first.
    case requiresSetup(String)
    /// The account's plan doesn't include the API (Neon Free, Cloudflare Enterprise contracts).
    case planNotSupported(String)
    /// No internet connection.
    case offline
    /// A timeout, DNS failure, TLS failure, or a dropped connection.
    case network
    /// The provider had a server error.
    case server(status: Int)
    /// The provider answered with a status Kill Cord didn't expect.
    case unexpectedStatus(Int)
    /// The response wasn't in the documented shape. The API may have changed.
    case unexpectedResponse

    public init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            self = .offline
        default:
            self = .network
        }
    }

    /// Maps an HTTP failure. Adapters pass a hint for 403s naming the permission their key needs.
    public static func from(status: Int, headers: [String: String] = [:], missingScopeHint: String) -> SpendError {
        switch status {
        case 401: return .invalidKey
        case 403: return .missingScope(hint: missingScopeHint)
        case 429:
            let retryAfter = headers["retry-after"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            return .rateLimited(retryAfter: retryAfter)
        case 500...599: return .server(status: status)
        default: return .unexpectedStatus(status)
        }
    }

    /// Worth retrying on its own, with backoff. The rest wait for the person to change something.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .offline, .network, .server, .unexpectedStatus, .unexpectedResponse: true
        case .notConfigured, .invalidKey, .missingScope, .noUsageAPI, .requiresSetup, .planNotSupported: false
        }
    }

    /// A short label for the panel: "Key rejected", "Offline".
    public var shortLabel: String {
        switch self {
        case .notConfigured: "Not connected"
        case .invalidKey: "Key rejected"
        case .missingScope: "Missing permission"
        case .rateLimited: "Rate limited"
        case .noUsageAPI: "No spend API"
        case .requiresSetup: "Needs setup"
        case .planNotSupported: "Not on this plan"
        case .offline: "Offline"
        case .network: "Can't connect"
        case .server: "Provider error"
        case .unexpectedStatus: "Request failed"
        case .unexpectedResponse: "Unexpected response"
        }
    }

    /// The full sentence, naming the provider.
    public func message(for provider: ProviderID) -> String { // swiftlint:disable:this cyclomatic_complexity
        let name = provider.info.name
        switch self {
        case .notConfigured:
            return "\(name) isn't connected. Add a key in Settings › Providers."
        case .invalidKey:
            return "\(name) rejected the key. It may be revoked, expired, or the wrong kind (\(name) needs "
                + "\(provider.info.keyKind.lowercased()))."
        case .missingScope(let hint):
            return "The key works, but \(name) won't let it read billing. \(hint)"
        case .rateLimited(let retryAfter):
            let wait = retryAfter.map { " Trying again in \(SpendText.duration($0))." } ?? " Trying again later."
            return "\(name) asked Kill Cord to slow down." + wait
        case .noUsageAPI:
            return "\(name) has no API for spend, so Kill Cord can't show it. The caps audit still works."
        case .requiresSetup(let what):
            return "\(name) needs setup first: \(what)"
        case .planNotSupported(let what):
            return what
        case .offline:
            return "Your Mac is offline. Showing the last spend Kill Cord read, which isn't live."
        case .network:
            return "Couldn't reach \(name). Kill Cord will try again."
        case .server(let status):
            return "\(name) had a server error (HTTP \(status)). Kill Cord will try again."
        case .unexpectedStatus(let status):
            return "\(name) answered with HTTP \(status). Kill Cord will try again."
        case .unexpectedResponse:
            return "\(name) answered in a shape Kill Cord doesn't recognize. Its API may have changed; check "
                + "for a Kill Cord update."
        }
    }
}

extension SpendError: LocalizedError {
    public var errorDescription: String? { shortLabel }
}
