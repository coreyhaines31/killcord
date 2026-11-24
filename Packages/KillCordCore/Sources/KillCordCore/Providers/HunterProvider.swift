// Hunter credits and quotas.
// Reference: https://hunter.io/api-documentation/v2#account (OpenAPI: https://hunter.io/openapi.json, getAccount)
//
// GET https://api.hunter.io/v2/account
//   headers: X-API-KEY: <API key>   ("in the api_key query parameter, in the X-API-KEY header, or … Bearer")
//   200:     { "data": { "plan_name": "Growth", "reset_date": "2026-12-02",
//                        "requests": { "credits": { "used": 550.0, "available": 10000.0, "remaining": 9450.0 },
//                                      "searches": { "used": 550, "available": 10000, "remaining": 9450 },
//                                      "verifications": { "used": 1100, "available": 20000, "remaining": 18900 } } } }
// "This call is free." `credits` is "only present when the team has a single credits pool"; without it,
// searches and verifications are separate quotas. Use `remaining`: `available` includes extra credit packs.
// Errors: { "errors": [ { "id": "…", "code": 401, "details": "…" } ] }. Hunter answers 403 for the rate limit.
import Foundation

public struct HunterProvider: SpendProvider {
    public let id = ProviderID.hunter
    static let accountURL = URL(string: "https://api.hunter.io/v2/account")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "")
    }

    struct Reply: Decodable {
        let data: Account

        struct Account: Decodable {
            let resetDate: String?
            let requests: Requests

            enum CodingKeys: String, CodingKey {
                case resetDate = "reset_date"
                case requests
            }
        }

        struct Requests: Decodable {
            let credits: Quota?
            let searches: Quota?
        }

        struct Quota: Decodable {
            let used: FlexibleDecimal
            let available: FlexibleDecimal
            let remaining: FlexibleDecimal
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply: Reply
        do {
            reply = try await api.get(Reply.self, Self.accountURL, headers: ["X-API-KEY": key])
        } catch SpendError.missingScope {
            // "403 - Forbidden: You have reached the rate limit."
            throw SpendError.rateLimited(retryAfter: nil)
        }
        let account = reply.data
        let (quota, unit) = if let credits = account.requests.credits {
            (credits, "credits")
        } else if let searches = account.requests.searches {
            (searches, "searches")
        } else {
            throw SpendError.unexpectedResponse
        }
        let balance = Balance(remaining: quota.remaining.value, unit: .units(unit), kind: .allowance,
                              limit: quota.available.value, used: quota.used.value,
                              resetsAt: account.resetDate.flatMap(Self.day))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    /// "2026-12-02", the start of that day in UTC.
    static func day(_ text: String) -> Date? {
        ISO8601.date(text + "T00:00:00Z")
    }
}
