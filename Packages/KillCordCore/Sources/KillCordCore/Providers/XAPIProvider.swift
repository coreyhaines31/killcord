// X API pay-per-use credit balance.
// Reference: https://docs.x.com/x-api/usage/get-usage-credits (overview: https://docs.x.com/x-api/usage/introduction)
// Pricing, spending limits, auto-recharge: https://docs.x.com/x-api/getting-started/pricing
//
// GET https://api.x.com/2/usage/credits
//   headers: Authorization: Bearer <the app's Bearer token>   (an OAuth 2.0 user token also works)
//   200:     { "data": { "total_balance": 12.5, "prepaid_balance": 10, "free_balance": 2.5,
//                        "free_grants": [ { … } ] } }
// "Returns the payer's developer-platform credit balance in USD. total_balance is max(0, prepaid_balance +
// free_balance); prepaid_balance may be negative." Errors are problem objects with `title` and `detail`.
import Foundation

public struct XAPIProvider: SpendProvider {
    public let id = ProviderID.xapi
    static let creditsURL = URL(string: "https://api.x.com/2/usage/credits")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the Bearer token of an app on a pay-per-use account.")
    }

    struct Credits: Decodable {
        let data: Balances

        struct Balances: Decodable {
            let totalBalance: FlexibleDecimal

            enum CodingKeys: String, CodingKey {
                case totalBalance = "total_balance"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(Credits.self, Self.creditsURL, headers: ["Authorization": "Bearer \(key)"])
        let balance = Balance.usd(reply.data.totalBalance.value)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
