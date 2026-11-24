// Bland AI credit balance.
// Reference: https://docs.bland.ai/api-v1/get/me
// The docs call `current_balance` a "number of credits" and state no credit-to-dollar rate, so it reads as credits
// with no dollar estimate (https://docs.bland.ai/platform/billing).
// Restricted keys: https://docs.bland.ai/api-v1/post/keys-create ("Every restricted key can also read your account
// details (`GET /v1/me`)").
//
// GET https://api.bland.ai/v1/me
//   headers: authorization: <API key>   (no "Bearer")
//   200:     { "status": "active", "billing": { "current_balance": 99919.1210000034, "refill_to": null },
//              "total_calls": 9903 }
// Errors: { "status": "error", "data": null, "errors": [{ "error": "UNAUTHORIZED", "message": "…" }] }.
import Foundation

public struct BlandProvider: SpendProvider {
    public let id = ProviderID.bland
    static let meURL = URL(string: "https://api.bland.ai/v1/me")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a Bland API key. Any restricted key can read the "
            + "balance.")
    }

    struct Account: Decodable {
        let billing: Billing

        struct Billing: Decodable {
            let currentBalance: FlexibleDecimal

            enum CodingKeys: String, CodingKey {
                case currentBalance = "current_balance"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let account = try await api.get(Account.self, Self.meURL, headers: ["authorization": key])
        let balance = Balance(remaining: account.billing.currentBalance.value, unit: .units("credits"))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
