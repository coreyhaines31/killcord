// xAI prepaid credit balance, from the Management API.
// Reference: https://docs.x.ai/developers/rest-api-reference/management/billing
// Management keys: https://docs.x.ai/developers/management-api-guide
//
// GET https://management-api.x.ai/v1/billing/teams/{team_id}/prepaid/balance
//   headers: Authorization: Bearer <management key>   (separate from the API keys that call models)
//   200:     { "changes": [ … ], "total": { "val": "-1000" } }
// Amounts are strings of USD cents. Credit is negative: a PURCHASE's amount "will be negative" and a SPEND's
// "will be positive", so "-1000" is $10.00 of credit left. The team ID is on
// https://console.x.ai/team/default/settings/team. The docs show no error body for these routes.
import Foundation

public struct XAIProvider: SpendProvider {
    public let id = ProviderID.xai
    static let base = URL(string: "https://management-api.x.ai/v1/billing/teams/")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a management key from the team whose balance you "
            + "want, and check the team ID.")
    }

    struct PrepaidBalance: Decodable {
        let total: Cents

        struct Cents: Decodable {
            let val: FlexibleDecimal
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("managementKey")
        let team = try credentials.require("teamID")
        // The ID goes into the path, so only the characters an ID can have.
        guard team.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else {
            throw SpendError.requiresSetup("the team ID doesn't look right. Copy it from Settings › Team.")
        }
        let url = Self.base.appendingPathComponent(team).appendingPathComponent("prepaid/balance")
        let balance = try await api.get(PrepaidBalance.self, url, headers: ["Authorization": "Bearer \(key)"])
        let credit = Self.credit(cents: balance.total.val.value)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: .usd(credit), fetchedAt: now)
    }

    /// xAI signs credit negative and spend positive, in cents.
    static func credit(cents: Decimal) -> Decimal { -cents / 100 }
}
