// DigitalOcean month-to-date usage.
// Reference (OpenAPI): https://github.com/digitalocean/openapi/blob/main/specification/resources/billing/balance_get.yml
// and its model: …/billing/models/balance.yml. Scope: https://docs.digitalocean.com/reference/api/scopes/billing/read/
//
// GET https://api.digitalocean.com/v2/customers/my/balance
//   headers: Authorization: Bearer <token>   (needs billing:read)
//   200:     { "month_to_date_balance": "23.44", "account_balance": "12.23", "month_to_date_usage": "11.21",
//              "generated_at": "2019-07-09T15:01:12Z" }
// Amounts are USD strings. `month_to_date_usage` is "Amount used in the current billing period as of the
// `generated_at` time". The balances are what's owed, not prepaid credit, so Kill Cord shows only the usage.
// Errors: { "id": "unauthorized", "message": "Unable to authenticate you." }.
import Foundation

public struct DigitalOceanProvider: SpendProvider {
    public let id = ProviderID.digitalocean
    static let balanceURL = URL(string: "https://api.digitalocean.com/v2/customers/my/balance")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Create a custom-scoped token with the billing:read scope.")
    }

    struct CustomerBalance: Decodable {
        let monthToDateUsage: FlexibleDecimal
        let generatedAt: String?

        enum CodingKeys: String, CodingKey {
            case monthToDateUsage = "month_to_date_usage"
            case generatedAt = "generated_at"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(CustomerBalance.self, Self.balanceURL, headers: ["Authorization": "Bearer \(key)"])
        return SpendSnapshot(provider: id, today: nil, month: Money(reply.monthToDateUsage.value),
                             dataAsOf: reply.generatedAt.flatMap(ISO8601.date), fetchedAt: now)
    }
}
