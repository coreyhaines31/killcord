import Foundation

/// More services Kill Cord reads a prepaid balance or plan allowance from: GPU clouds, model hosts, media
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
        )
    ]
}
