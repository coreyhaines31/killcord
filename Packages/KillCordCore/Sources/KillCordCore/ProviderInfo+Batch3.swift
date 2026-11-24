import Foundation

/// The services added in the third batch: balances, allowances, spend and usage. Each one's API and key are
/// documented at the top of its adapter in `Providers/`.
extension ProviderInfo {
    static let batch3Providers: [ProviderInfo] = [
        ProviderInfo(
            id: .stability, name: "Stability AI", capability: .balance(spend: []),
            fields: [apiKeyField("Stability AI API key")],
            keyKind: "API key",
            keyURL: url("https://platform.stability.ai/dashboard/api-keys"),
            keyPowerWarning: "Stability AI documents one kind of API key, with no scopes or read-only option. It "
                + "can run every API, which spends your credits. Kill Cord only reads the credit balance.",
            lag: ProviderLag(typical: 0, note: "Stability AI doesn't say how current the credit balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://platform.stability.ai/dashboard/billing")
        ),
        ProviderInfo(
            id: .moonshot, name: "Kimi (Moonshot AI)", capability: .balance(spend: []),
            fields: [apiKeyField("sk-admin-…", help: "An Admin key with the billing:read scope, or an inference "
                + "API key.")],
            keyKind: "Admin key with the billing:read scope",
            keyURL: url("https://platform.kimi.ai/console"),
            keyPowerWarning: "Kimi's Admin keys carry only the scopes chosen when they're made, and Kimi says they "
                + "\"cannot call any inference endpoint\". One with only billing:read reads bills, usage and the "
                + "balance. An inference API key also works, but it has no scopes and can make paid model calls on "
                + "your balance. Kill Cord only reads the balance.",
            lag: ProviderLag(typical: 0, note: "Kimi doesn't say how current the balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://platform.kimi.ai/console")
        ),
        ProviderInfo(
            id: .exa, name: "Exa", capability: .balance(spend: []),
            fields: [apiKeyField("Exa service key", help: "A service key from the Service keys tab, not a "
                + "search API key.")],
            keyKind: "Team Management service key",
            keyURL: url("https://dashboard.exa.ai/api-keys"),
            keyPowerWarning: "Exa reads team credits only through its Team Management API, with a service key. "
                + "A service key can create, update, rotate and delete your team's API keys, and Exa documents no "
                + "read-only one. Exa turns the API on per team when you ask support@exa.ai. Kill Cord only reads "
                + "the credit balance.",
            lag: ProviderLag(typical: 5 * 60, note: "Exa says the balance can lag recent usage by up to 5 "
                + "minutes."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://dashboard.exa.ai/billing")
        ),
        ProviderInfo(
            id: .scrapingbee, name: "ScrapingBee", capability: .balance(spend: []),
            fields: [apiKeyField("ScrapingBee API key")],
            keyKind: "API key",
            keyURL: url("https://dashboard.scrapingbee.com/account/manage/api_key"),
            keyPowerWarning: "ScrapingBee documents one API key per account, with no scopes or read-only option. It "
                + "can run scrapes that use your plan's credits. Kill Cord only reads credit usage, which "
                + "ScrapingBee says doesn't add to your concurrency.",
            lag: ProviderLag(typical: 0, note: "ScrapingBee says usage results are available in real time."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://app.scrapingbee.com/billing/plans")
        ),
        ProviderInfo(
            id: .scrapfly, name: "Scrapfly", capability: .balance(spend: []),
            fields: [apiKeyField("Scrapfly API key", help: "The LIVE key of a project.")],
            keyKind: "API key",
            keyURL: url("https://scrapfly.io/dashboard/project"),
            keyPowerWarning: "Scrapfly gives each project one key per environment (LIVE and TEST), and a key reaches "
                + "every Scrapfly product. Scrapfly documents no read-only key, so this one can run scrapes that use "
                + "your plan's credits. Scrapfly takes the key in the request address; Kill Cord removes it from "
                + "any error it shows. Kill Cord only reads your account's credit usage.",
            lag: ProviderLag(typical: 0, note: "Scrapfly doesn't say how current the account usage is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://scrapfly.io/dashboard/billing")
        ),
        ProviderInfo(
            id: .kie, name: "Kie.ai", capability: .balance(spend: []),
            fields: [apiKeyField("Kie.ai API key")],
            keyKind: "API key",
            keyURL: url("https://kie.ai/api-key"),
            keyPowerWarning: "Kie.ai documents one kind of API key, with no scopes or read-only option. It can start "
                + "generations that use your credits. Kie.ai lets a key carry hourly, daily and total usage caps and "
                + "an IP allow list, so give this one small caps. Kill Cord only reads the credit balance.",
            lag: ProviderLag(typical: 0, note: "Kie.ai doesn't say how current the credit balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://kie.ai/logs")
        ),
        ProviderInfo(
            id: .bland, name: "Bland AI", capability: .balance(spend: []),
            fields: [apiKeyField("org_s_…", help: "A restricted key with only Analytics read, if your organization "
                + "has restricted keys.")],
            keyKind: "Restricted API key with only Analytics read",
            keyURL: url("https://app.bland.ai/dashboard/settings"),
            keyPowerWarning: "Bland says every restricted key can read your account details, which hold the "
                + "balance. A restricted key with only Analytics read can also read analytics summaries, but it "
                + "can't place calls, send messages, or change agents. Bland is still rolling restricted keys out "
                + "by organization. Without them, a full-access key acts as the admin who made it and can place "
                + "calls on your credits. Kill Cord only reads the balance.",
            lag: ProviderLag(typical: 0, note: "Bland doesn't say how current the balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://app.bland.ai/dashboard/pay")
        ),
        ProviderInfo(
            id: .llamacloud, name: "LlamaCloud", capability: .monthDollars,
            fields: [
                apiKeyField("llx-…", help: "A key from the User API Keys table, not a project key."),
                CredentialField(id: "organizationID", label: "Organization ID", placeholder: "Organization ID",
                                isSecret: false, isOptional: true,
                                help: "Needed only if the key sees more than one organization."),
                CredentialField(id: "region", label: "Region", isSecret: false,
                                help: "Where the LlamaCloud account lives.", choices: ["US", "EU"])
            ],
            keyKind: "User API key",
            keyURL: url("https://cloud.llamaindex.ai/?target=api-key"),
            keyPowerWarning: "LlamaCloud says \"An API key inherits its owner's privileges\": there's no read-only "
                + "or billing-only key. Organization usage needs a key from the User API Keys table, which some "
                + "plans don't offer; a project key can't read it. Make the key from the member with the least "
                + "access that can read the organization, since a key from an admin can manage the organization. "
                + "Kill Cord only reads usage and the plan's limits.",
            lag: ProviderLag(typical: 0, note: "LlamaCloud doesn't say how current the invoice total is. The month "
                + "is your billing period."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://cloud.llamaindex.ai")
        )
    ]
}
