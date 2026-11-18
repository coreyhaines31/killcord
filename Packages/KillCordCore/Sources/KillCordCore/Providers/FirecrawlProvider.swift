// Firecrawl team credit usage.
// Reference: https://docs.firecrawl.dev/api-reference/endpoint/credit-usage
//
// GET https://api.firecrawl.dev/v2/team/credit-usage
//   headers: Authorization: Bearer <API key> (from https://www.firecrawl.dev/app/api-keys)
//   200:     { "success": true, "data": { "remainingCredits": 1000, "planCredits": 500000,
//              "billingPeriodStart": "2025-01-01T00:00:00Z" | null, "billingPeriodEnd": "2025-01-31T23:59:59Z" | null } }
// `remainingCredits` includes coupon and pay-as-you-go credits; `planCredits` doesn't, so the two aren't
// shown as "x of y". Errors: { "success": false, "error": "…" }.
import Foundation

public struct FirecrawlProvider: SpendProvider {
    public let id = ProviderID.firecrawl
    static let usageURL = URL(string: "https://api.firecrawl.dev/v2/team/credit-usage")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from the team you want to watch.")
    }

    struct Usage: Decodable {
        let success: Bool
        let data: Details?

        struct Details: Decodable {
            let remainingCredits: FlexibleDecimal
            let billingPeriodEnd: String?
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let usage = try await api.get(Usage.self, Self.usageURL, headers: ["Authorization": "Bearer \(key)"])
        guard usage.success, let details = usage.data else { throw SpendError.unexpectedResponse }
        let reset = details.billingPeriodEnd.flatMap(ISO8601.date)
        let balance = Balance(remaining: details.remainingCredits.value, unit: .units("credits"),
                              kind: reset == nil ? .prepaid : .allowance, resetsAt: reset)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
