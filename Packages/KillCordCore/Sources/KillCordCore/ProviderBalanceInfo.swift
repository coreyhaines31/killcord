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
        ),
        ProviderInfo(
            id: .elevenlabs, name: "ElevenLabs", capability: .balance(spend: []),
            fields: [apiKeyField("sk_…", help: "A key limited to User read access.")],
            keyKind: "API key with User read access",
            keyURL: url("https://elevenlabs.io/app/settings/api-keys"),
            keyPowerWarning: "ElevenLabs lets you limit a key to some endpoints and give it a credit quota. A key "
                + "with every endpoint on can make speech on your credits. Turn off everything but User (read): "
                + "Kill Cord only reads your subscription's credits. ElevenLabs doesn't document which permission "
                + "that call needs. If the key is refused, also give it read access to User.",
            lag: ProviderLag(typical: 0, note: "ElevenLabs doesn't say how current the credit count is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://elevenlabs.io/app/subscription")
        ),
        ProviderInfo(
            id: .xai, name: "xAI", capability: .balance(spend: []),
            fields: [
                CredentialField(id: "managementKey", label: "Management key", placeholder: "Management API key",
                                isSecret: true, help: "From Settings › Management Keys, not an API key."),
                CredentialField(id: "teamID", label: "Team ID", placeholder: "65c1e471-205f-…", isSecret: false,
                                help: "On Settings › Team in the xAI Console.")
            ],
            keyKind: "Management API key",
            keyURL: url("https://console.x.ai/team/default/management-keys"),
            keyPowerWarning: "xAI has no read-only management key. A management key can create, change, and "
                + "delete API keys, top up your prepaid credits with the default payment method, and change "
                + "spending limits. Kill Cord only reads the prepaid balance, and the key stays in your Mac's "
                + "Keychain. Revoke it in the xAI Console if it leaks.",
            lag: ProviderLag(typical: 0, note: "xAI doesn't say how current the prepaid balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://console.x.ai/team/default/billing")
        ),
        ProviderInfo(
            id: .deepseek, name: "DeepSeek", capability: .balance(spend: []),
            fields: [apiKeyField("sk-…")],
            keyKind: "API key",
            keyURL: url("https://platform.deepseek.com/api_keys"),
            keyPowerWarning: "DeepSeek documents no read-only or limited key. An API key can make paid model calls "
                + "until the balance runs out. Create one just for Kill Cord so you can revoke it on its own. Kill "
                + "Cord only reads the balance.",
            lag: ProviderLag(typical: 0, note: "DeepSeek doesn't say how current the balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://platform.deepseek.com/top_up")
        ),
        ProviderInfo(
            id: .apify, name: "Apify", capability: .balance(spend: [.month]),
            fields: [apiKeyField("apify_api_…")],
            keyKind: "API token",
            keyURL: url("https://console.apify.com/settings/integrations"),
            keyPowerWarning: "Apify has no read-only token. By default a token can access all data in your account "
                + "and run Actors on it. Apify's scoped tokens can be limited to chosen resources, but its docs "
                + "don't say which permission reads usage limits. Kill Cord only reads this cycle's usage and "
                + "your usage limit.",
            lag: ProviderLag(typical: 0, note: "Apify doesn't say how current usage is. The month is Apify's "
                + "usage cycle, which may not start on the 1st."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://console.apify.com/billing#/limits")
        ),
        ProviderInfo(
            id: .tavily, name: "Tavily", capability: .balance(spend: []),
            fields: [apiKeyField("tvly-…")],
            keyKind: "API key",
            keyURL: url("https://app.tavily.com"),
            keyPowerWarning: "Tavily doesn't document a read-only key. An API key can run searches, extracts, and "
                + "crawls that use your credits. Tavily lets a key carry its own credit limit, so set a small one. "
                + "Kill Cord only reads usage.",
            lag: ProviderLag(typical: 0, note: "Tavily doesn't say how current usage is. Its usage call allows "
                + "10 requests every 10 minutes, so Kill Cord checks it at most every 15 minutes."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://app.tavily.com/billing")
        ),
        ProviderInfo(
            id: .deepgram, name: "Deepgram", capability: .balance(spend: []),
            fields: [
                apiKeyField("Deepgram API key", help: "A key with the Admin role."),
                CredentialField(id: "projectID", label: "Project ID", placeholder: "Project ID", isSecret: false,
                                isOptional: true,
                                help: "Only if the key can see more than one project.")
            ],
            keyKind: "API key with the Admin role",
            keyURL: url("https://console.deepgram.com"),
            keyPowerWarning: "Deepgram has no read-only key for balances. Its role table gives billing:read to the "
                + "Admin and Owner roles only, and an Admin key can also manage the project's keys and members "
                + "and make paid requests. Deepgram lets you create a key with chosen scopes, but its docs don't "
                + "say which scope the balance call needs. Kill Cord only reads balances.",
            lag: ProviderLag(typical: 0, note: "Deepgram doesn't say how current balances are."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://console.deepgram.com")
        ),
        ProviderInfo(
            id: .runway, name: "Runway", capability: .balance(spend: []),
            fields: [apiKeyField("key_…")],
            keyKind: "API key",
            keyURL: url("https://dev.runway.com/"),
            keyPowerWarning: "Runway doesn't document a read-only or scoped key. An API key can start image and "
                + "video generations that use your credits. Create one just for Kill Cord so you can revoke it on "
                + "its own. Kill Cord only reads the credit balance.",
            lag: ProviderLag(typical: 0, note: "Runway doesn't say how current the credit balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://dev.runway.com/usage")
        ),
        ProviderInfo(
            id: .serpapi, name: "SerpApi", capability: .balance(spend: []),
            fields: [apiKeyField("Private API key")],
            keyKind: "Private API key",
            keyURL: url("https://serpapi.com/dashboard"),
            keyPowerWarning: "SerpApi has a single private key with no scopes or read-only form. It can run "
                + "searches that use your plan. SerpApi sends the key in the address of each request, as its API "
                + "requires; Kill Cord removes it from any error it shows. Kill Cord only reads your account, "
                + "which SerpApi says is free and doesn't count toward your monthly searches.",
            lag: ProviderLag(typical: 0, note: "SerpApi doesn't say how current the search count is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://serpapi.com/dashboard")
        )
    ]
}
