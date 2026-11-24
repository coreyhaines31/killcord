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
        )
    ]
}
