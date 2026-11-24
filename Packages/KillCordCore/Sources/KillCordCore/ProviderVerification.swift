import Foundation

/// Whether a built-in provider's adapter has been checked against a real account, or only built from the
/// provider's documentation. Unverified providers are labeled Beta wherever they're shown, until someone
/// confirms one with a live account (tracked in issue 212).
public enum ProviderVerification: Hashable, Sendable {
    /// Read with a real account at least once.
    case liveVerified
    /// Built from the provider's documented API and never called with a real key.
    case beta
    /// Not read by a built-in adapter (a custom connection or a manual entry), so it keeps its own labels.
    case notApplicable

    public var isBeta: Bool { self == .beta }

    /// The providers used with real accounts. Every provider added since 0.3.1 starts in beta, so a new
    /// adapter is labeled until it's added here.
    static let verifiedProviders: Set<ProviderID> = [
        .anthropic, .google, .openai, .vercel, .cloudflare, .twilio, .neon, .supabase,
        .openrouter, .dataforseo, .ahrefs, .firecrawl, .treg, .monid
    ]

    public static func of(_ provider: ProviderID) -> ProviderVerification {
        switch provider {
        case .custom, .manual: .notApplicable
        default: verifiedProviders.contains(provider) ? .liveVerified : .beta
        }
    }

    public static let betaLabel = "Beta"
    public static let betaDetail = "Not yet verified with a live account. Numbers come from the provider's "
        + "documented API."
    /// Added under an error from a beta provider, beside a link to `issuesURL`.
    public static let betaErrorLine = "This provider is in beta. If this looks wrong, report it"
    public static let issuesURL = URL(string: Brand.repository + "/issues")!
}

extension ProviderInfo {
    public var verification: ProviderVerification { .of(id) }
}

extension ProviderID {
    public var isBeta: Bool { ProviderVerification.of(self).isBeta }
}
