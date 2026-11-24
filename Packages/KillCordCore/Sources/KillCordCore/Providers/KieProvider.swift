// Kie.ai credit balance.
// Reference: https://docs.kie.ai/common-api/get-account-credits
// Pricing: https://kie.ai/pricing ("1 credit ≈ $0.005").
//
// GET https://api.kie.ai/api/v1/chat/credit
//   headers: Authorization: Bearer <API key>
//   200:     { "code": 200, "msg": "success", "data": 100.5 }
// "The HTTP status is 200 even when the request fails, so always check this field": `code` 200 means success, 401
// an invalid key, 402 insufficient credits, 429 a rate limit, 455 maintenance, 500 an error; `msg` says why.
import Foundation

public struct KieProvider: SpendProvider {
    public let id = ProviderID.kie
    static let creditURL = URL(string: "https://api.kie.ai/api/v1/chat/credit")!
    /// Kie.ai's pricing page: about $0.005 a credit. Shown only as a labeled estimate.
    static let dollarsPerCredit = Decimal(string: "0.005")!
    static let missingScopeHint = "Use an API key from the API Key page on kie.ai."

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: Self.missingScopeHint)
    }

    struct Reply: Decodable {
        let code: Int
        let data: FlexibleDecimal?
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let request = HTTPRequest(url: Self.creditURL, headers: ["Authorization": "Bearer \(key)"])
        let response = try await api.send(request)
        let reply = try api.decode(Reply.self, from: response)
        guard reply.code == 200 else {
            // The failure is in the body, not the HTTP status. Map it the same way, with Kie's own message.
            throw SpendError.from(status: reply.code, missingScopeHint: Self.missingScopeHint,
                                  detail: ProviderErrorDetail.message(in: response.body, sentWith: request))
        }
        guard let credits = reply.data else { throw SpendError.unexpectedResponse }
        let balance = Balance(remaining: credits.value, unit: .units("credits"), dollarsPerUnit: Self.dollarsPerCredit)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
