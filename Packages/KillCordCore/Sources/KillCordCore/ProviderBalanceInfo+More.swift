import Foundation

/// More services Kill Cord reads a prepaid balance, plan allowance, or spend from: GPU clouds, model hosts, media
/// generators, cloud hosts, messaging, and data APIs. Each one's API and key are documented at the top of its
/// adapter in `Providers/`. Kept apart from `balanceProviders` so the two lists grow without colliding.
extension ProviderInfo {
    static let moreBalanceProviders: [ProviderInfo] = [
        ProviderInfo(
            id: .runpod, name: "Runpod", capability: .balance(spend: []),
            fields: [apiKeyField("Runpod API key", help: "A Read Only key, or Restricted with billing:read.")],
            keyKind: "API key with billing read access",
            keyURL: url("https://console.runpod.io/user/credentials"),
            keyPowerWarning: "Runpod keys can be All, Restricted, or Read Only. Runpod says a Read Only key has "
                + "read access without write access, and its docs say the balance call needs the billing:read "
                + "scope. Don't use an All key: it can start Pods and Serverless workers on your balance. Kill "
                + "Cord only reads the balance.",
            lag: ProviderLag(typical: 5 * 60, note: "Runpod bills running resources every 5 minutes."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://www.console.runpod.io/user/billing")
        ),
        ProviderInfo(
            id: .deepinfra, name: "DeepInfra", capability: .monthDollars,
            fields: [apiKeyField("DeepInfra API key", help: "A scoped key with only billing:read.")],
            keyKind: "API key scoped to billing:read",
            keyURL: url("https://deepinfra.com/dash/keys"),
            keyPowerWarning: "DeepInfra keys carry scopes. With only billing:read, DeepInfra says the key can "
                + "\"Read usage, invoices, key spending limits and request costs\", and no API key can change "
                + "payment details, set spending limits, or top up. A new key starts with inference and other "
                + "scopes, and an unrestricted key can run models on your account, so untick everything but "
                + "billing:read. Kill Cord only reads this month's usage.",
            lag: ProviderLag(typical: 0, note: "DeepInfra doesn't say how far behind its usage runs, or which "
                + "time zone its months follow. Kill Cord reads the month by its UTC name."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://deepinfra.com/dash/billing")
        ),
        ProviderInfo(
            id: .xapi, name: "X API", capability: .balance(spend: []),
            fields: [apiKeyField("App Bearer token", help: "From your app's Keys and tokens.")],
            keyKind: "app Bearer token",
            keyURL: url("https://console.x.com"),
            keyPowerWarning: "The X API has no billing-only token. The app's Bearer token reads public X data, and "
                + "on pay-per-use every read is paid from your credits. Use an app made just for Kill Cord so you can "
                + "regenerate its token on its own. Kill Cord only reads the credit balance.",
            lag: ProviderLag(typical: 0, note: "X says credits are deducted in real time as you make requests."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://console.x.com")
        ),
        ProviderInfo(
            id: .bfl, name: "Black Forest Labs", capability: .balance(spend: []),
            fields: [apiKeyField("bfl_…")],
            keyKind: "API key",
            keyURL: url("https://dashboard.bfl.ai"),
            keyPowerWarning: "Black Forest Labs keys are scoped to a project, but BFL documents no read-only key: "
                + "any key can generate images and video that use your credits. Make a key just for Kill Cord so "
                + "you can delete it on its own. Kill Cord only reads the credit balance.",
            lag: ProviderLag(typical: 0, note: "BFL doesn't say how current the credit balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://dashboard.bfl.ai")
        ),
        ProviderInfo(
            id: .digitalocean, name: "DigitalOcean", capability: .monthDollars,
            fields: [apiKeyField("DigitalOcean API token", help: "A custom-scoped token with only billing:read.")],
            keyKind: "API token with the billing:read scope",
            keyURL: url("https://cloud.digitalocean.com/account/api/tokens"),
            keyPowerWarning: "DigitalOcean tokens can have custom scopes. With only billing:read, DigitalOcean says "
                + "the token can \"View and receive billing and invoice information\" and nothing else. Read Only "
                + "and Full Access tokens reach far more of your team, so don't use them. Kill Cord only reads your "
                + "balance and usage.",
            lag: ProviderLag(typical: 0, note: "DigitalOcean reports the time it last generated the figures, and "
                + "Kill Cord shows that time. Its docs don't say how often that is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://cloud.digitalocean.com/account/billing")
        ),
        ProviderInfo(
            id: .telnyx, name: "Telnyx", capability: .balance(spend: []),
            fields: [apiKeyField("Telnyx API key")],
            keyKind: "API key",
            keyURL: url("https://portal.telnyx.com/#/app/api-keys"),
            keyPowerWarning: "Telnyx documents no read-only or scoped key. An API key works for the whole account: "
                + "it can send messages, place calls, buy numbers, and change settings. Make a key just for Kill "
                + "Cord so you can revoke it on its own. Kill Cord only reads the balance and the auto recharge "
                + "setting.",
            lag: ProviderLag(typical: 0, note: "Telnyx doesn't say how current the balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://portal.telnyx.com")
        ),
        ProviderInfo(
            id: .luma, name: "Luma AI", capability: .balance(spend: []),
            fields: [apiKeyField("luma-api-…")],
            keyKind: "API key",
            keyURL: url("https://platform.lumalabs.ai"),
            keyPowerWarning: "Luma's balance call takes the same API key you generate with, so the key can start "
                + "image and video generations that use your credits. Luma's read-only Admin keys can't spend, but "
                + "they're for enterprise accounts and can't call the balance endpoint. Kill Cord only reads the "
                + "credit balance.",
            lag: ProviderLag(typical: 0, note: "The balance already leaves out credits held for generations still "
                + "running."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://app.lumalabs.ai/usage")
        ),
        ProviderInfo(
            id: .heygen, name: "HeyGen", capability: .balance(spend: []),
            fields: [apiKeyField("HeyGen API key", help: "A key restricted to account:read.")],
            keyKind: "API key restricted to account:read",
            keyURL: url("https://platform.heygen.com/api-keys"),
            keyPowerWarning: "HeyGen keys take permission scopes of the form resource:read or resource:write. The "
                + "balance call needs only account:read, and HeyGen says a read grant never satisfies a write "
                + "requirement, so that key can't make videos. Full-access keys (*:*) can. Kill Cord only reads your "
                + "balance, auto reload and spending cap.",
            lag: ProviderLag(typical: 0, note: "HeyGen doesn't say how current the balance is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://platform.heygen.com")
        ),
        ProviderInfo(
            id: .browseruse, name: "Browser Use", capability: .balance(spend: []),
            fields: [apiKeyField("Browser Use API key")],
            keyKind: "API key",
            keyURL: url("https://cloud.browser-use.com/settings"),
            keyPowerWarning: "Browser Use documents no read-only key. A key belongs to a project and can run agents "
                + "and browser sessions on that project's credits. Give the key Kill Cord uses a small monthly "
                + "spending cap. Kill Cord only reads the balance.",
            lag: ProviderLag(typical: 0, note: "Browser Use says running and simultaneous work can change the "
                + "balance while you read it."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://cloud.browser-use.com/settings?tab=billing")
        ),
        ProviderInfo(
            id: .novita, name: "Novita AI", capability: .balance(spend: []),
            fields: [apiKeyField("Novita API key")],
            keyKind: "API key",
            keyURL: url("https://novita.ai/settings/key-management"),
            keyPowerWarning: "Novita AI documents no read-only or scoped key. An API key can call models, run "
                + "sandboxes and start GPU instances that bill your balance. Make a key just for Kill Cord so you "
                + "can revoke it on its own. Kill Cord only reads the balance.",
            lag: ProviderLag(typical: 0, note: "Novita says pending charges currently default to zero, so recent "
                + "usage may not be in the balance yet."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://novita.ai/billing")
        ),
        ProviderInfo(
            id: .baseten, name: "Baseten", capability: .dollars,
            fields: [apiKeyField("Baseten API key")],
            keyKind: "API key",
            keyURL: url("https://app.baseten.co/settings/api_keys"),
            keyPowerWarning: "Baseten has no billing-only key, and its docs don't say which team key permission can "
                + "read billing. A personal API key carries all of your account's permissions: it can deploy, call "
                + "and train models, and an admin's can manage the workspace. Baseten requires personal keys to "
                + "expire within 90 days and revokes them after 30 days unused. Kill Cord only reads the usage summary.",
            lag: ProviderLag(typical: 0, note: "Baseten reports whole UTC days. It doesn't say how soon usage "
                + "appears."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://app.baseten.co")
        )
    ]
}
