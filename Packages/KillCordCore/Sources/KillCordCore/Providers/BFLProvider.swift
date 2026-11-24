// Black Forest Labs (FLUX API) credit balance.
// Reference: https://docs.bfl.ai/api-reference/get-the-users-credits
// Pricing ("1 credit = $0.01 USD"): https://docs.bfl.ai/quick_start/pricing
// Keys (scoped to projects, format bfl_…): https://docs.bfl.ai/account_management/organizations_projects
//
// GET https://api.bfl.ai/v1/credits
//   headers: x-key: <API key>
//   200:     { "credits": 1234.5 }   ("User's current credit balance")
// Status codes: https://docs.bfl.ai/api_integration/errors (402 means not enough credits, 403 no access).
import Foundation

public struct BFLProvider: SpendProvider {
    public let id = ProviderID.bfl
    static let creditsURL = URL(string: "https://api.bfl.ai/v1/credits")!
    /// "1 credit = $0.01 USD".
    static let dollarsPerCredit = Decimal(string: "0.01")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from a project in your BFL organization.")
    }

    struct Credits: Decodable {
        let credits: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(Credits.self, Self.creditsURL, headers: ["x-key": key])
        let balance = Balance(remaining: reply.credits.value, unit: .units("credits"),
                              dollarsPerUnit: Self.dollarsPerCredit)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
