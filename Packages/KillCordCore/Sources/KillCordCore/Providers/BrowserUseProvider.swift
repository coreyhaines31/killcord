// Browser Use Cloud credit balance.
// Reference: https://docs.browser-use.com/cloud/api-v2/billing/get-account-billing
// Billing guide (projects, auto recharge, key spending caps): https://docs.browser-use.com/cloud/guides/billing
//
// GET https://api.browser-use.com/api/v2/billing/account
//   headers: X-Browser-Use-API-Key: <API key>   (no Bearer prefix)
//   200:     { "totalCreditsBalanceUsd": 42.5, "monthlyCreditsBalanceUsd": 0, "additionalCreditsBalanceUsd": 42.5,
//              "concurrentSessionLimit": 50, "activeSessionCount": 0, "planInfo": null, "projectId": "…", … }
// "Credits belong to a project. All keys in that project use its balance." A null planInfo is normal for
// pay-as-you-go. 404 means "Project for a given API key not found!"; errors carry { "detail": … }.
import Foundation

public struct BrowserUseProvider: SpendProvider {
    public let id = ProviderID.browseruse
    static let accountURL = URL(string: "https://api.browser-use.com/api/v2/billing/account")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from the project whose credits you want.")
    }

    struct Account: Decodable {
        let totalCreditsBalanceUsd: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let account = try await api.get(Account.self, Self.accountURL, headers: ["X-Browser-Use-API-Key": key])
        let balance = Balance.usd(account.totalCreditsBalanceUsd.value)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
