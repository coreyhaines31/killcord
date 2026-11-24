// lemlist team credits.
// Reference: https://developer.lemlist.com/api-reference/endpoints/team/get-team-credits
//
// GET https://api.lemlist.com/api/team/credits
//   headers: Authorization: Basic base64(":" + <API key>)   ("the login is always empty and the password is the API key")
//   200:     { "credits": 100, "details": { "remaining": { "total": 100, "freemium": 0, "subscription": 80,
//                                                         "gifted": 10, "paid": 10 } } }
// `credits` is the "Total credits remaining". Errors are plain text: 401 "The authentication you supplied is
// incorrect", 403 "User linked to this API key is blocked", 404 "No user found for this API key".
import Foundation

public struct LemlistProvider: SpendProvider {
    public let id = ProviderID.lemlist
    static let creditsURL = URL(string: "https://api.lemlist.com/api/team/credits")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "lemlist says the user linked to this key is blocked.")
    }

    struct Credits: Decodable {
        let credits: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let basic = Data(":\(key)".utf8).base64EncodedString()
        let reply = try await api.get(Credits.self, Self.creditsURL, headers: ["Authorization": "Basic \(basic)"])
        let balance = Balance(remaining: reply.credits.value, unit: .units("credits"))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
