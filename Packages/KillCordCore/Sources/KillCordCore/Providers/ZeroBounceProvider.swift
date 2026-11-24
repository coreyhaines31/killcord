// ZeroBounce credit balance.
// Reference: https://www.zerobounce.net/docs/email-validation-api-quickstart/v2-credit-balance
//
// GET https://api.zerobounce.net/v2/getcredits?api_key=<API key>
//   200:     { "Credits": "2375323" }
// "'Credits' is the value that shows the number of credits left in your account for email validations. If a -1
// is returned, that means your API Key is invalid." The key travels in the query string, which
// ProviderErrorDetail removes from any message it shows.
import Foundation

public struct ZeroBounceProvider: SpendProvider {
    public let id = ProviderID.zerobounce

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from your ZeroBounce account.")
    }

    struct Credits: Decodable {
        let credits: FlexibleDecimal

        enum CodingKeys: String, CodingKey {
            case credits = "Credits"
        }
    }

    static func creditsURL(key: String) -> URL {
        var components = URLComponents(string: "https://api.zerobounce.net/v2/getcredits")!
        components.queryItems = [URLQueryItem(name: "api_key", value: key)]
        return components.url!
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(Credits.self, Self.creditsURL(key: key), headers: [:])
        guard reply.credits.value >= 0 else { throw SpendError.invalidKey }
        let balance = Balance(remaining: reply.credits.value, unit: .units("credits"))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
