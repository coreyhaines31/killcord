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
        ),
        ProviderInfo(
            id: .cartesia, name: "Cartesia", capability: .usageUnitsOnly,
            fields: [apiKeyField("sk_car_admin_…", help: "An admin key. Standard keys can't read usage.")],
            keyKind: "Admin key",
            keyURL: url("https://play.cartesia.ai/keys/admin"),
            keyPowerWarning: "Cartesia reads credit usage only with an admin key, which only organization admins can "
                + "make. Cartesia documents no read-only admin key: one can also list and remove your "
                + "organization's users and send or cancel invites. It can't call the speech APIs. Kill Cord only "
                + "reads credits used.",
            lag: ProviderLag(typical: 0, note: "Cartesia doesn't say how current credit usage is. It reports "
                + "credits used, not money or credits left."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://play.cartesia.ai/usage")
        ),
        ProviderInfo(
            id: .together, name: "Together AI", capability: .monthDollars,
            fields: [apiKeyField("Together API key")],
            keyKind: "API key",
            keyURL: url("https://api.together.ai/settings/projects/~current/api-keys"),
            keyPowerWarning: "Together has no read-only key. Its docs say anyone holding a key \"has full access to "
                + "its project's resources and can spend your credit balance\". The billing report covers the "
                + "whole organization, and any project's key can read it. Kill Cord only reads the report.",
            lag: ProviderLag(typical: 24 * 3600, note: "Together finalizes daily usage through the end of "
                + "yesterday (UTC), so this month's number leaves out today."),
            billingTimeZone: utc, minimumRefreshInterval: 60 * 60,
            consoleURL: url("https://api.together.ai/settings/organization/~current/billing")
        ),
        ProviderInfo(
            id: .fireworks, name: "Fireworks AI", capability: .dollars,
            fields: [
                apiKeyField("Fireworks API key", help: "A key from a service account or user with the Inference user role."),
                CredentialField(id: "accountID", label: "Account ID", placeholder: "my-account", isSecret: false,
                                isOptional: true, help: "Needed only if the key sees more than one account.")
            ],
            keyKind: "API key from an Inference user",
            keyURL: url("https://app.fireworks.ai/settings/users/api-keys"),
            keyPowerWarning: "Fireworks has no read-only or billing-only key: a key carries its user's role, and "
                + "Fireworks says any key on the account can read billing. The least-powerful role, Inference user, "
                + "\"can view all resources and run inference, but cannot create or modify resources\", so this "
                + "key can still run models on your account. Kill Cord only reads the billing summary and the spend "
                + "limit.",
            lag: ProviderLag(typical: 60 * 60, note: "Fireworks doesn't say how far behind the billing summary "
                + "runs. Its amounts are before credits are applied, so they can differ from the invoice."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://fireworks.ai/billing")
        ),
        ProviderInfo(
            id: .vapi, name: "Vapi", capability: .dollars,
            fields: [apiKeyField("Vapi private key")],
            keyKind: "Private API key",
            keyURL: url("https://dashboard.vapi.ai/org/api-keys"),
            keyPowerWarning: "Vapi has no read-only key. It says \"A private key can access everything in your "
                + "organization\", so this key can start calls and change assistants. Public keys are only for "
                + "client SDKs. Kill Cord only runs an analytics query that adds up call costs.",
            lag: ProviderLag(typical: 0, note: "Vapi doesn't say how far behind call costs run. Only calls are "
                + "counted, not other usage."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://dashboard.vapi.ai")
        ),
        ProviderInfo(
            id: .retell, name: "Retell AI", capability: .dollars,
            fields: [apiKeyField("Retell API key", help: "A key with only the History › Read permission.")],
            keyKind: "API key with only History › Read",
            keyURL: url("https://dashboard.retellai.com"),
            keyPowerWarning: "Retell keys have full access by default, but can be limited by permission. Retell says "
                + "\"a key that only pulls call history needs just History › Read\", which covers call and chat "
                + "history, transcripts, recordings, and call metadata. That's sensitive, but it can't start calls or "
                + "change agents. Kill Cord only adds up call costs.",
            lag: ProviderLag(typical: 0, note: "A call's cost appears once it ends. Chats and subscription items "
                + "such as phone numbers aren't counted."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://dashboard.retellai.com")
        ),
        ProviderInfo(
            id: .browserbase, name: "Browserbase", capability: .usageUnitsOnly,
            fields: [
                apiKeyField("Browserbase API key"),
                CredentialField(id: "projectID", label: "Project ID", placeholder: "Project ID", isSecret: false,
                                isOptional: true, help: "Needed only if the key sees more than one project.")
            ],
            keyKind: "Project API key",
            keyURL: url("https://www.browserbase.com/settings"),
            keyPowerWarning: "Browserbase gives each project one API key, with no scopes or read-only option; only "
                + "an admin can regenerate it. It can start browser sessions that use your plan's hours and proxy "
                + "data. Kill Cord only reads the project's usage.",
            lag: ProviderLag(typical: 0, note: "Browserbase doesn't say how current usage is, or what period it "
                + "covers. It reports minutes and bytes, not dollars."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://www.browserbase.com/overview")
        ),
        ProviderInfo(
            id: .resend, name: "Resend", capability: .usageUnitsOnly,
            fields: [apiKeyField("re_…", help: "A key with Full access. Sending access keys can't read.")],
            keyKind: "API key with Full access",
            keyURL: url("https://resend.com/api-keys"),
            keyPowerWarning: "Resend has two kinds of key, and neither is read-only. A Sending access key \"can only "
                + "send emails\", and Resend refuses it on every other request, so Kill Cord can't use it. A Full "
                + "access key \"can create, delete, get, and update any resource\", including domains and other "
                + "keys. Kill Cord only lists one domain to read the quota headers Resend sends back.",
            lag: ProviderLag(typical: 0, note: "Resend reports emails used, not dollars or the plan's quota. Sent "
                + "and received emails both count."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://resend.com/settings/usage")
        ),
        ProviderInfo(
            id: .postmark, name: "Postmark", capability: .usageUnitsOnly,
            fields: [apiKeyField("Server API token", help: "From the server's API Tokens tab.")],
            keyKind: "Server API token",
            keyURL: url("https://account.postmarkapp.com/servers"),
            keyPowerWarning: "Postmark has no read-only token. Stats need a Server API token, which has the "
                + "server's full privileges, including sending email that counts toward your bill. An Account token "
                + "can't read stats. Kill Cord only reads the server's sent counts.",
            lag: ProviderLag(typical: 0, note: "Postmark doesn't say how current its stats are. It reports emails "
                + "sent, not dollars."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://account.postmarkapp.com/servers")
        ),
        ProviderInfo(
            id: .mistral, name: "Mistral", capability: .monthDollars,
            fields: [apiKeyField("Mistral Admin API key", help: "From the Admin Panel's enterprise section. A "
                + "standard API key won't work.")],
            keyKind: "Admin API key",
            keyURL: url("https://admin.mistral.ai/"),
            keyPowerWarning: "Mistral reads spend only through its Admin API, which is in beta and only on "
                + "Enterprise plans. An Admin API key \"grants access to that Organization's admin endpoints\": it "
                + "can invite and remove users, manage workspaces and API keys, and change the spending limit. "
                + "Mistral has no read-only admin key. Kill Cord only reads usage against the spending limit.",
            lag: ProviderLag(typical: 0, note: "Mistral doesn't say how current usage against the limit is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://admin.mistral.ai/organization/usage")
        )
    ]
}
