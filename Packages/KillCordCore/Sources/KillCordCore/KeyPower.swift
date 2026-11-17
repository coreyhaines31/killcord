import Foundation

/// How much a provider's saved key can do beyond reading billing. A future "move this key to the cloud"
/// review uses it to pick its tone: a calm note for a read-only key, a clear warning for one that can
/// manage the organization. The details stay in `ProviderInfo.keyPowerWarning`.
public enum KeyPower: String, Sendable, Equatable, Codable {
    /// The provider offers a key scoped to billing reads, and Kill Cord's setup asks for that one.
    case readOnly
    /// A read-only key exists but isn't guaranteed: it depends on what the person chose when creating it.
    case readOnlyIfChosen
    /// The provider has no read-only key. This one can also change the account or organization.
    case canManage
    /// Nothing is saved for this provider.
    case noKey
}

extension ProviderID {
    public var keyPower: KeyPower {
        switch self {
        // Billing Read API token.
        case .cloudflare: .readOnly
        // A service account limited to BigQuery Data Viewer, Job User, and optionally Billing Account Viewer.
        case .google: .readOnly
        // A read-only admin key may be offered when it's created.
        case .openai: .readOnlyIfChosen
        // No read-only key. Vercel tokens can be scoped to a team, but not to billing.
        case .anthropic, .vercel, .twilio, .neon: .canManage
        case .supabase: .noKey
        }
    }
}
