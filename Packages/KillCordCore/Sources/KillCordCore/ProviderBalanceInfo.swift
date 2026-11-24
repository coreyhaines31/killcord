import Foundation

/// The services Kill Cord reads a prepaid balance or plan allowance from. Each one's API and key are
/// documented at the top of its adapter in `Providers/`.
extension ProviderInfo {
    static func apiKeyField(_ placeholder: String, help: String = "") -> CredentialField {
        CredentialField(id: "apiKey", label: "API key", placeholder: placeholder, isSecret: true, help: help)
    }

    static let balanceProviders: [ProviderInfo] = [
        ProviderInfo(
            id: .openrouter, name: "OpenRouter", capability: .balance(spend: [.today, .month]),
            fields: [apiKeyField("sk-or-v1-…", help: "Kill Cord reads this key's own limit and spend, not the "
                + "whole account's.")],
            keyKind: "API key",
            keyURL: url("https://openrouter.ai/settings/keys"),
            keyPowerWarning: "OpenRouter has no read-only key. An API key can make paid requests until its credit "
                + "limit. Create one just for Kill Cord with a small limit: Kill Cord only reads the key's limit "
                + "and usage. It can't manage your account or other keys.",
            lag: ProviderLag(typical: 5 * 60, note: "OpenRouter settles recent requests after a short delay. The "
                + "day and month follow UTC."),
            billingTimeZone: utc, minimumRefreshInterval: 5 * 60,
            consoleURL: url("https://openrouter.ai/settings/keys")
        ),
        ProviderInfo(
            id: .dataforseo, name: "DataForSEO", capability: .balance(spend: []),
            fields: [
                CredentialField(id: "login", label: "API login", placeholder: "you@example.com", isSecret: false,
                                help: "On the API Access page. Not always your sign-in email."),
                CredentialField(id: "password", label: "API password", placeholder: "API password", isSecret: true,
                                help: "The API password from the same page, not your dashboard password.")
            ],
            keyKind: "API login and password",
            keyURL: url("https://app.dataforseo.com/api-access"),
            keyPowerWarning: "DataForSEO has no read-only credential. The API login and password can run every paid "
                + "API call on your balance. Kill Cord only reads your account data, which DataForSEO doesn't charge "
                + "for, and the password stays in your Mac's Keychain.",
            lag: ProviderLag(typical: 0, note: "DataForSEO doesn't say how current the balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://app.dataforseo.com/")
        ),
        ProviderInfo(
            id: .ahrefs, name: "Ahrefs", capability: .balance(spend: []),
            fields: [apiKeyField("Ahrefs API key")],
            keyKind: "API key",
            keyURL: nil,
            keyPowerWarning: "Ahrefs doesn't document a read-only key. An API key can run API calls that use your "
                + "workspace's units. Ahrefs lets a key carry its own unit limit, so set a small one. Kill Cord "
                + "only reads limits and usage, which Ahrefs says uses no units.",
            lag: ProviderLag(typical: 0, note: "Ahrefs doesn't say how current unit usage is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://app.ahrefs.com/")
        ),
        ProviderInfo(
            id: .firecrawl, name: "Firecrawl", capability: .balance(spend: []),
            fields: [apiKeyField("fc-…")],
            keyKind: "API key",
            keyURL: url("https://www.firecrawl.dev/app/api-keys"),
            keyPowerWarning: "Firecrawl doesn't document a read-only key. An API key can run scrapes that use your "
                + "team's credits. Kill Cord only reads the credit balance.",
            lag: ProviderLag(typical: 0, note: "Firecrawl doesn't say how current the credit count is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://www.firecrawl.dev/app")
        ),
        ProviderInfo(
            id: .treg, name: "treg", capability: .balance(spend: []),
            fields: [
                CredentialField(id: "token", label: "Token", placeholder: "treg token", isSecret: true,
                                help: "A team or agent token. An agent token is made with treg org agent-new."),
                CredentialField(id: "org", label: "Team slug", placeholder: "acme", isSecret: false,
                                isOptional: true,
                                help: "Only for a personal sign-in token: the team whose balance to read.")
            ],
            keyKind: "Team or agent token",
            keyURL: url("https://treg.to/skill.md"),
            keyPowerWarning: "treg has no token that can read the balance but never spend. Every role, viewer "
                + "included, can call tools on the team's balance. Use an agent token, limited with treg's "
                + "options (treg org agent-new --help lists them). Kill Cord only reads the balance. If auto "
                + "top-up is on, reading the balance can start a top-up once it's under your trigger, as any "
                + "treg call does.",
            lag: ProviderLag(typical: 0, note: "treg's balance is live. Calls still running hold part of it."),
            billingTimeZone: utc, minimumRefreshInterval: 5 * 60,
            consoleURL: url("https://treg.to/")
        ),
        ProviderInfo(
            id: .monid, name: "Monid", capability: .balance(spend: []),
            fields: [apiKeyField("monid_live_…")],
            keyKind: "API key",
            keyURL: url("https://app.monid.ai/access/api-keys"),
            keyPowerWarning: "Monid doesn't document a read-only key. An API key can start paid runs on your "
                + "wallet. Kill Cord only reads the wallet balance. Workspace budgets and run caps in the Monid "
                + "dashboard limit what any key can spend.",
            lag: ProviderLag(typical: 0, note: "Monid doesn't say how current the wallet balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://app.monid.ai/")
        ),
        ProviderInfo(
            id: .fal, name: "fal", capability: .balance(spend: []),
            fields: [apiKeyField("key_id:key_secret", help: "A key with the BILLING preset.")],
            keyKind: "API key with the BILLING preset",
            keyURL: url("https://fal.ai/dashboard/keys"),
            keyPowerWarning: "fal's BILLING preset reads usage, invoices, billing settings, the list of keys, and "
                + "the model catalog. fal's docs list no other permission for it. A FULL key can also run models "
                + "on your credits, so don't use one. Kill Cord only reads the credit balance.",
            lag: ProviderLag(typical: 0, note: "fal doesn't say how current the credit balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://fal.ai/dashboard/billing")
        )
    ]
}
