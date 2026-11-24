// Magister API credit balance (the prepaid API wallet, not plan credits).
// Reference: https://magistermarketing.com/docs/api ("GET /v1/credits (free, `read`) returns `balance`, `held`,
// `available` and `price_per_credit_usd`"; OpenAPI: https://api.magistermarketing.com/v1/openapi.json).
// Keys: https://magistermarketing.com/docs/api/authentication ("A read-only key has only `read`: it can read your
// balance and jobs and run the free endpoints, and it can never spend credits").
//
// GET https://api.magistermarketing.com/v1/credits
//   headers: Authorization: Bearer mm_live_…
//   200:     { "data": { "balance": 1200, "held": 75, "available": 1125, "price_per_credit_usd": 0.02 },
//              "credits_charged": 0, "request_id": "…" }
// `available` is the balance less credits held by running requests. Errors: { "error", "message", "retryable" }.
import Foundation

public struct MagisterProvider: SpendProvider {
    public let id = ProviderID.magister
    static let creditsURL = URL(string: "https://api.magistermarketing.com/v1/credits")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a Magister API key with the read scope. A read-only "
            + "key has it.")
    }

    struct Reply: Decodable {
        let data: Credits

        struct Credits: Decodable {
            let available: FlexibleDecimal
            let pricePerCreditUsd: FlexibleDecimal?

            enum CodingKeys: String, CodingKey {
                case available
                case pricePerCreditUsd = "price_per_credit_usd"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let credits = try await api.get(Reply.self, Self.creditsURL, headers: ["Authorization": "Bearer \(key)"]).data
        let balance = Balance(remaining: credits.available.value, unit: .units("credits"),
                              dollarsPerUnit: credits.pricePerCreditUsd?.value)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
