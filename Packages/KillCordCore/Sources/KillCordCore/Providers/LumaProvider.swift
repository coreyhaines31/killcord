// Luma AI credit balance (the Luma API Platform, which Luma's older Dream Machine docs point to).
// Reference: https://docs.agents.lumalabs.ai/api/agents/operations/get-credit-balance/
// Guide: https://docs.agents.lumalabs.ai/guides/usage/ ("Credits and dollars": "Do not assume a default rate.")
// Errors: https://docs.agents.lumalabs.ai/guides/error-handling/
//
// GET https://agents.lumalabs.ai/v1/credits
//   headers: Authorization: Bearer <API key>   (the same key you generate with; keys start luma-api-)
//   200:     { "balance_credits": 49512 }
// "balance_credits is your team's whole balance: every credit granted or bought, less everything spent, less the
// credits held right now for generations still running." Errors: { "detail": { "code", "message", … } }.
import Foundation

public struct LumaProvider: SpendProvider {
    public let id = ProviderID.luma
    static let creditsURL = URL(string: "https://agents.lumalabs.ai/v1/credits")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a generation API key from the Luma developer "
            + "dashboard. Admin read-only keys can't read the balance.")
    }

    struct Credits: Decodable {
        let balanceCredits: FlexibleDecimal

        enum CodingKeys: String, CodingKey {
            case balanceCredits = "balance_credits"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(Credits.self, Self.creditsURL, headers: ["Authorization": "Bearer \(key)"])
        let balance = Balance(remaining: reply.balanceCredits.value, unit: .units("credits"))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
