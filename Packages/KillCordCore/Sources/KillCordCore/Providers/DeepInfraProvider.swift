// DeepInfra spend this month.
// Reference: https://docs.deepinfra.com/api-reference/billing/usage
// Scopes: https://docs.deepinfra.com/account/authentication.md#scopes ("billing:read: Read usage, invoices, key
// spending limits and request costs")
//
// GET https://api.deepinfra.com/payment/usage?from=2026.11
//   headers: Authorization: Bearer <API key>   (needs the billing:read scope)
//   200:     { "months": [ { "period": "2026.11", "interval": { "fr": 0, "to": 0 }, "items": [ … ],
//                            "total_cost": 1234, "invoice_id": "NOT_FINAL" } ],
//              "initial_month": "2025.03" }
// `from` is "YYYY.MM, current(-N), unix_timestamp"; without `to`, "a single month marked by from" comes back.
// `total_cost` is an integer, "total cost for all items in cents". The docs don't say which time zone a month
// follows, so Kill Cord asks for the month by its UTC name.
// A missing scope is a 403: { "detail": { "error": "this API key does not have the 'billing:read' scope" } }.
//
// /v1/me?checklist=true also has `stripe_balance` ("Negative value indicates funds ready-to-spend"), but its unit
// isn't documented and it needs account:read, so Kill Cord doesn't read it.
import Foundation

public struct DeepInfraProvider: SpendProvider {
    public let id = ProviderID.deepinfra

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Give the key the billing:read scope.")
    }

    struct Usage: Decodable {
        let months: [Month]

        struct Month: Decodable {
            let period: String
            let totalCost: Int

            enum CodingKeys: String, CodingKey {
                case period
                case totalCost = "total_cost"
            }
        }
    }

    static func usageURL(_ window: BillingWindow) -> URL {
        var components = URLComponents(string: "https://api.deepinfra.com/payment/usage")!
        components.queryItems = [URLQueryItem(name: "from", value: period(window))]
        return components.url!
    }

    /// "2026.11", DeepInfra's name for a month.
    static func period(_ window: BillingWindow) -> String {
        window.monthKey.replacingOccurrences(of: "-", with: ".")
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let window = window(now)
        let usage = try await api.get(Usage.self, Self.usageURL(window), headers: ["Authorization": "Bearer \(key)"])
        // No entry for the month means nothing was billed in it yet.
        let cents = usage.months.first { $0.period == Self.period(window) }?.totalCost
        guard usage.months.isEmpty || cents != nil else { throw SpendError.unexpectedResponse }
        let month = Money(Decimal(cents ?? 0) / 100)
        return SpendSnapshot(provider: id, today: nil, month: month, fetchedAt: now)
    }
}
