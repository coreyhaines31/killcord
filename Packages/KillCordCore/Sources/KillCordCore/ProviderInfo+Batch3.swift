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
        )
    ]
}
