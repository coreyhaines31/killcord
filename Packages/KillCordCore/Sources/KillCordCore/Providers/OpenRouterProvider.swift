// OpenRouter key limits and usage.
// Reference: https://openrouter.ai/docs/api-reference/limits
// Units: https://openrouter.ai/docs/faq ("OpenRouter uses a credit system where the base currency is US dollars.")
//
// GET https://openrouter.ai/api/v1/key
//   headers: Authorization: Bearer <API key>
//   200:     { "data": { "limit": 100 | null, "limit_remaining": 74.5 | null, "limit_reset": "monthly" | null,
//              "usage": 25.5, "usage_daily": 1.2, "usage_weekly": 6, "usage_monthly": 25.5, … } }
// Everything is for this key only, not the whole account (that needs a management key, /api/v1/credits).
// Usage windows are UTC: the day at 00:00 UTC, the month on the 1st. BYOK usage is reported apart and isn't
// counted. A key with no limit has no balance to show.
import Foundation

public struct OpenRouterProvider: SpendProvider {
    public let id = ProviderID.openrouter
    static let keyURL = URL(string: "https://openrouter.ai/api/v1/key")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from Settings › API Keys.")
    }

    struct Key: Decodable {
        let data: Details

        struct Details: Decodable {
            let limit: FlexibleDecimal?
            let limitRemaining: FlexibleDecimal?
            let limitReset: String?
            let usageDaily: FlexibleDecimal
            let usageMonthly: FlexibleDecimal

            enum CodingKeys: String, CodingKey {
                case limit
                case limitRemaining = "limit_remaining"
                case limitReset = "limit_reset"
                case usageDaily = "usage_daily"
                case usageMonthly = "usage_monthly"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let details = try await api.get(Key.self, Self.keyURL, headers: ["Authorization": "Bearer \(key)"]).data
        var balance: Balance?
        if let remaining = details.limitRemaining?.value {
            let resets = details.limitReset != nil
            balance = Balance.usd(remaining, kind: resets ? .allowance : .prepaid, limit: details.limit?.value)
        }
        return SpendSnapshot(provider: id, today: Money(details.usageDaily.value),
                             month: Money(details.usageMonthly.value), balance: balance, fetchedAt: now)
    }
}
