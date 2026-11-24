// Runway credit balance.
// Reference: https://docs.dev.runwayml.com/api (GET /v1/organization)
// Price: https://docs.dev.runwayml.com/guides/pricing ("One credit costs $0.01.")
//
// GET https://api.dev.runwayml.com/v1/organization
//   headers: Authorization: Bearer key_<…>, X-Runway-Version: 2024-11-06 (required)
//   200:     { "creditBalance": 1234, "tier": { "maxMonthlyCreditSpend": 10000, "models": { … } },
//              "usage": { "models": { … } } }
// `creditBalance` is "the number of credits remaining in the organization account", an integer. The tier's
// maximum caps credits bought in a month, not used, so it isn't shown as a limit. Errors: { "error": "…" }.
import Foundation

public struct RunwayProvider: SpendProvider {
    public let id = ProviderID.runway
    static let organizationURL = URL(string: "https://api.dev.runwayml.com/v1/organization")!
    static let apiVersion = "2024-11-06"
    /// Runway's documented price of one credit.
    static let dollarsPerCredit = Decimal(string: "0.01")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from the Runway project you want to watch.")
    }

    struct Organization: Decodable {
        let creditBalance: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let organization = try await api.get(Organization.self, Self.organizationURL,
                                             headers: ["Authorization": "Bearer \(key)",
                                                       "X-Runway-Version": Self.apiVersion])
        let balance = Balance(remaining: organization.creditBalance.value, unit: .units("credits"),
                              dollarsPerUnit: Self.dollarsPerCredit)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
