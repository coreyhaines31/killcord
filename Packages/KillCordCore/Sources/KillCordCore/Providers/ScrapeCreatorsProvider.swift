// ScrapeCreators credit balance.
// Reference: https://docs.scrapecreators.com/v1/credit-balance (OpenAPI: https://docs.scrapecreators.com/openapi.json)
//
// GET https://api.scrapecreators.com/v1/account/credit-balance
//   headers: x-api-key: <API key>
//   200:     { "success": true, "creditCount": 333, "message": "You have 333 credits remaining." }
// "Checking your balance is free and does not deduct any credits." Credits are bought in packs and don't reset.
// The docs show no error body; a 402 means the credits ran out.
import Foundation

public struct ScrapeCreatorsProvider: SpendProvider {
    public let id = ProviderID.scrapecreators
    static let balanceURL = URL(string: "https://api.scrapecreators.com/v1/account/credit-balance")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the API key from your ScrapeCreators dashboard.")
    }

    struct CreditBalance: Decodable {
        let success: Bool?
        let creditCount: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(CreditBalance.self, Self.balanceURL, headers: ["x-api-key": key])
        guard reply.success != false else { throw SpendError.unexpectedResponse }
        let balance = Balance(remaining: reply.creditCount.value, unit: .units("credits"))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
