// Scrapfly plan credits.
// Reference: https://scrapfly.io/docs/account
//
// GET https://api.scrapfly.io/account?key=<API key>   (the query parameter is Scrapfly's canonical way to send it;
//                                                     ProviderErrorDetail strips query values from errors)
//   200: { "account": { "currency": "USD", … }, "project": { "budget_limit": 700, "budget_spent": 0, … },
//          "subscription": { "plan_name": "FREE", "period": { "start": "2020-07-24", "end": "2020-08-24" },
//                            "usage": { "scrape": { "current": 0, "limit": 500, "remaining": 500, … }, … } } }
// Scrape usage is in API credits. Period dates are days, read as UTC.
import Foundation

public struct ScrapflyProvider: SpendProvider {
    public let id = ProviderID.scrapfly
    static let accountURL = URL(string: "https://api.scrapfly.io/account")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the LIVE API key of a project on your Scrapfly "
            + "account.")
    }

    struct Account: Decodable {
        let subscription: Subscription

        struct Subscription: Decodable {
            let period: Period?
            let usage: Usage
        }

        struct Period: Decodable {
            let end: String
        }

        struct Usage: Decodable {
            let scrape: Scrape
        }

        struct Scrape: Decodable {
            let current: FlexibleDecimal
            let limit: FlexibleDecimal
            let remaining: FlexibleDecimal
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let url = Self.accountURL.adding([URLQueryItem(name: "key", value: key)])
        let account = try await api.get(Account.self, url, headers: [:])
        let scrape = account.subscription.usage.scrape
        let balance = Balance(remaining: max(scrape.remaining.value, 0), unit: .units("credits"), kind: .allowance,
                              limit: scrape.limit.value, used: scrape.current.value,
                              resetsAt: account.subscription.period.flatMap { Self.day($0.end) })
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    /// "2020-08-24" as midnight UTC.
    static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
