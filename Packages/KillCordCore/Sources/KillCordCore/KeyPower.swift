import Foundation

/// How much a provider's saved key can do beyond reading billing. A future "move this key to the cloud"
/// review uses it to pick its tone: a calm note for a read-only key, a clear warning for one that can
/// manage the organization. The details stay in `ProviderInfo.keyPowerWarning`.
public enum KeyPower: String, Sendable, Equatable, Codable {
    /// The provider offers a key scoped to billing reads, and Kill Cord's setup asks for that one.
    case readOnly
    /// A read-only key exists but isn't guaranteed: it depends on what the person chose when creating it.
    case readOnlyIfChosen
    /// No read-only key, but this one can't change the account either: it can make paid calls (an
    /// OpenRouter or Firecrawl key).
    case canSpend
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
        // fal's BILLING preset lists only billing reads; a FULL key could run models.
        case .fal: .readOnlyIfChosen
        // No read-only key. An Anthropic service account or personal key has its linked account's
        // permissions, and the docs don't name a role limited to the cost report. Vercel tokens can be
        // scoped to a team, but not to billing.
        case .anthropic, .vercel, .twilio, .neon: .canManage
        // Nothing secret: a manual entry is a plan and a date.
        case .supabase, .manual: .noKey
        // Keys that can make paid calls but, as far as each provider documents, not manage the account.
        // DataForSEO's API password, treg's tokens (every role can call tools), and Monid, Firecrawl and Ahrefs
        // keys have no read-only form. OpenRouter's account settings need a separate management key.
        case .openrouter, .dataforseo, .ahrefs, .firecrawl, .treg, .monid: .canSpend
        // Unknown: Kill Cord can't know what another service's key can do, so it assumes the worst.
        case .custom: .canManage
        }
    }
}
