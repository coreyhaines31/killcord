// Stability AI credit balance.
// Reference: https://docs.stability.ai/api-reference/user/account-balance
// Credits: https://platform.stability.ai/pricing ("1 credit = $0.01").
//
// GET https://api.stability.ai/v1/user/balance
//   headers: Authorization: Bearer <API key>
//   200:     { "credits": 0.6336833840314097 }
// `credits` is a number. Errors: { "id": "…", "name": "unauthorized", "message": "missing authorization header" }.
import Foundation

public struct StabilityProvider: SpendProvider {
    public let id = ProviderID.stability
    static let balanceURL = URL(string: "https://api.stability.ai/v1/user/balance")!
    /// Stability's pricing page: 1 credit = $0.01.
    static let dollarsPerCredit = Decimal(string: "0.01")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from the API Keys page on the Stability AI "
            + "platform.")
    }

    struct Account: Decodable {
        let credits: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let account = try await api.get(Account.self, Self.balanceURL, headers: ["Authorization": "Bearer \(key)"])
        let balance = Balance(remaining: account.credits.value, unit: .units("credits"),
                              dollarsPerUnit: Self.dollarsPerCredit)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
