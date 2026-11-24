// Exa team credit balance, from the Team Management API.
// Reference: https://exa.ai/docs/reference/team-management/get-team-credits
// Spec: https://exa.ai/docs/team-management-spec.yaml. Billing: https://exa.ai/docs/admin/billing
//
// GET https://admin-api.exa.ai/team-management/credits
//   headers: x-api-key: <service key>   (the API is enabled per team; service keys come from the Service keys tab)
//   200:     { "credits_usd": 412.37, "expiring_credits": [{ "amount_usd": 20.00, "expires_at": "…" }],
//              "metadata": { "generated_at": "…" } }
// `credits_usd` is a number in dollars, and "can lag recent usage by up to 5 minutes".
// Errors: { "error": "Unauthorized" }; 404 { "error": "No billing account found for this team." }.
import Foundation

public struct ExaProvider: SpendProvider {
    public let id = ProviderID.exa
    static let creditsURL = URL(string: "https://admin-api.exa.ai/team-management/credits")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a service key from the Service keys tab. Exa turns "
            + "on the Team Management API per team, on request.")
    }

    struct Credits: Decodable {
        let creditsUsd: FlexibleDecimal

        enum CodingKeys: String, CodingKey {
            case creditsUsd = "credits_usd"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let credits = try await api.get(Credits.self, Self.creditsURL, headers: ["x-api-key": key])
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: .usd(credits.creditsUsd.value),
                             fetchedAt: now)
    }
}
