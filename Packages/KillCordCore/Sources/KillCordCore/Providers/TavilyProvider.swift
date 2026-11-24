// Tavily plan credits.
// Reference: https://docs.tavily.com/documentation/api-reference/endpoint/usage
// Rate limit: https://docs.tavily.com/documentation/rate-limits ("10 requests per 10 minutes" for /usage)
//
// GET https://api.tavily.com/usage
//   headers: Authorization: Bearer tvly-<key>
//   200:     { "key": { "usage": 150, "limit": 1000 | null, … },
//              "account": { "current_plan": "Bootstrap", "plan_usage": 500, "plan_limit": 15000,
//                           "paygo_usage": 25, "paygo_limit": 100, … } }
// Credits for the current billing cycle. Pay-as-you-go is counted apart from the plan, so Kill Cord shows the
// plan's credits and doesn't add the two. Errors: { "detail": { "error": "…" } }.
import Foundation

public struct TavilyProvider: SpendProvider {
    public let id = ProviderID.tavily
    static let usageURL = URL(string: "https://api.tavily.com/usage")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from the workspace you want to watch.")
    }

    struct Usage: Decodable {
        let account: Account

        struct Account: Decodable {
            let planUsage: FlexibleDecimal?
            let planLimit: FlexibleDecimal?

            enum CodingKeys: String, CodingKey {
                case planUsage = "plan_usage"
                case planLimit = "plan_limit"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let usage = try await api.get(Usage.self, Self.usageURL, headers: ["Authorization": "Bearer \(key)"])
        // A pay-as-you-go-only account has no plan credits: nothing to show, rather than a made-up zero.
        var balance: Balance?
        if let limit = usage.account.planLimit?.value, limit > 0, let used = usage.account.planUsage?.value {
            balance = Balance(remaining: max(limit - used, 0), unit: .units("credits"), kind: .allowance,
                              limit: limit, used: used)
        }
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
