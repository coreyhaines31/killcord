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
        // Runpod offers Read Only keys, and Restricted keys scoped to billing:read; an All key can start Pods.
        case .runpod: .readOnlyIfChosen
        // DeepInfra keys take scopes; billing:read only reads usage, invoices and key limits.
        case .deepinfra: .readOnly
        // The X API's app Bearer token makes paid reads on the credits; there's no billing-only token.
        case .xapi: .canSpend
        // Black Forest Labs keys are scoped to a project, not to reads: any key can generate images.
        case .bfl: .canSpend
        // DigitalOcean custom-scoped tokens can hold only billing:read, which views billing and invoices.
        case .digitalocean: .readOnly
        // Telnyx documents no key scopes: an API key can do anything in the account.
        case .telnyx: .canManage
        // Keys that can make paid calls but, as far as each provider documents, not manage the account.
        // DataForSEO's API password, treg's tokens (every role can call tools), and Monid, Firecrawl and Ahrefs
        // keys have no read-only form. OpenRouter's account settings need a separate management key.
        case .openrouter, .dataforseo, .ahrefs, .firecrawl, .treg, .monid: .canSpend
        // ElevenLabs keys can be limited to some endpoints; one limited to User read can't make speech.
        case .elevenlabs: .readOnlyIfChosen
        // An xAI management key can also create and delete API keys, top up, and change spending limits.
        case .xai: .canManage
        // DeepSeek documents no key scopes: every key can make paid model calls.
        case .deepseek: .canSpend
        // Apify tokens can access all account data by default; no read-only token is documented.
        case .apify: .canManage
        // Tavily documents no read-only key; any key can run searches on the plan's credits.
        case .tavily: .canSpend
        // Deepgram gives billing:read only to Admin and Owner roles, which can manage the project's keys.
        case .deepgram: .canManage
        // Runway documents no key scopes: a key can start generations that use credits.
        case .runway: .canSpend
        // SerpApi has one private key per account, with no scopes: it can run searches.
        case .serpapi: .canSpend
        // Bright Data's Finance level reaches billing pages, and its docs don't call any key read-only.
        case .brightdata: .canManage
        // ScrapeCreators documents one API key per team, with no scopes: it can run scrapes.
        case .scrapecreators: .canSpend
        // Stability AI documents one kind of API key, with no scopes: it can run generations.
        case .stability: .canSpend
        // Kimi Admin keys carry chosen scopes and can't call inference; billing:read alone reads bills.
        case .moonshot: .readOnlyIfChosen
        // Exa's Team Management service keys create, rotate and delete API keys; none is read-only.
        case .exa: .canManage
        // ScrapingBee has one API key per account, with no documented scopes: it can run scrapes.
        case .scrapingbee: .canSpend
        // Scrapfly has one key per project environment, giving access to every product: it can scrape.
        case .scrapfly: .canSpend
        // Kie.ai documents one kind of API key with no scopes, only usage caps and an IP allow list.
        case .kie: .canSpend
        // Unknown: Kill Cord can't know what another service's key can do, so it assumes the worst.
        case .custom: .canManage
        }
    }
}
