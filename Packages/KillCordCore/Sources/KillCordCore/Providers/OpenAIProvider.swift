// OpenAI Administration API, organization costs and spend limits.
// Costs: https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs/
// Spend limit: https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/spend_limit
// Guide: https://developers.openai.com/api/docs/guides/spend-limits
//
// GET https://api.openai.com/v1/organization/costs
//   headers: Authorization: Bearer <Admin API key, sk-admin…>
//   query:   start_time (Unix seconds, inclusive, required), end_time (exclusive), bucket_width=1d (the only
//            width), limit (1 to 180 buckets), page (the previous response's next_page)
//   200:     { object: "page", data: [{ object: "bucket", start_time, end_time,
//              results: [{ object: "organization.costs.result", amount: { value: 0.06, currency: "usd" } }] }],
//              has_more, next_page }
// `amount.value` is a number in the currency's major unit (dollars). The reference doesn't spell the unit
// out; OpenAI's own cookbook sums it as USD. It's decoded straight into Decimal, never Double.
//
// GET https://api.openai.com/v1/organization/spend_limit
//   200: { object: "organization.spend_limit", threshold_amount: 10000 (cents), currency: "USD",
//          interval: "month", enforcement: { status: "enforcing" | "inactive" } }
// The reference describes status as "whether the hard spend limit is currently enforcing" and its examples
// pair "inactive" with a 0 threshold, so "enforcing" with a threshold is read as "a hard limit is on".
import Foundation

public struct OpenAIProvider: SpendProvider {
    public let id = ProviderID.openai
    static let costsURL = URL(string: "https://api.openai.com/v1/organization/costs")!
    static let spendLimitURL = URL(string: "https://api.openai.com/v1/organization/spend_limit")!
    public static let hardLimitCapID = "openai.org-hard-limit"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an Admin API key from Settings › Organization › "
            + "Admin keys, with read access to usage.")
    }

    struct Page: Decodable {
        struct Bucket: Decodable {
            let startTime: Int
            let results: [Result]

            enum CodingKeys: String, CodingKey {
                case startTime = "start_time"
                case results
            }
        }

        struct Result: Decodable {
            struct Amount: Decodable {
                let value: FlexibleDecimal
                let currency: String
            }

            let amount: Amount?
        }

        let data: [Bucket]
        let hasMore: Bool?
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    struct SpendLimit: Decodable {
        struct Enforcement: Decodable {
            let status: String
        }

        let thresholdAmount: Int?
        let currency: String?
        let enforcement: Enforcement?

        enum CodingKeys: String, CodingKey {
            case thresholdAmount = "threshold_amount"
            case currency
            case enforcement
        }
    }

    func headers(_ key: String) -> [String: String] {
        ["Authorization": "Bearer \(key)", "accept": "application/json"]
    }

    func costsURL(from start: Date, to end: Date, limit: Int, page: String?) -> URL {
        var items = [
            URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int(end.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let page { items.append(URLQueryItem(name: "page", value: page)) }
        return Self.costsURL.adding(items)
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        let key = try credentials.require("apiKey")
        let window = window(now)
        _ = try await api.get(Page.self, costsURL(from: window.dayStart, to: window.dayEnd, limit: 1, page: nil),
                              headers: headers(key))
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let window = window(now)
        var buckets: [Page.Bucket] = []
        var page: String?
        for _ in 0..<6 {
            let response = try await api.get(Page.self, costsURL(from: window.monthStart, to: window.dayEnd,
                                                                 limit: 31, page: page), headers: headers(key))
            buckets += response.data
            guard response.hasMore == true, let next = response.nextPage else { break }
            page = next
        }
        var month = Money.zero()
        var today = Money.zero()
        let todayStart = Int(window.dayStart.timeIntervalSince1970)
        for bucket in buckets {
            for result in bucket.results {
                guard let amount = result.amount else { continue }
                let money = Money(amount.value.value, Currency(amount.currency))
                guard money.currency == .usd else { throw SpendError.unexpectedResponse }
                month = month + money
                if bucket.startTime >= todayStart { today = today + money }
            }
        }
        return SpendSnapshot(provider: id, today: today, month: month, fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let key = credentials["apiKey"],
              let limit = try? await api.get(SpendLimit.self, Self.spendLimitURL, headers: headers(key))
        else { return [] }
        let cents = limit.thresholdAmount ?? 0
        let amount = MoneyText.string(.fromCents(cents, Currency(limit.currency ?? "USD")))
        let status: CapVerification.Status
        if cents > 0, limit.enforcement?.status == "enforcing" {
            status = .on("OpenAI reports a hard limit of \(amount) a month.")
        } else if cents > 0 {
            status = .off("OpenAI has a \(amount) limit saved, but reports it isn't enforced.")
        } else {
            status = .off("OpenAI reports no organization hard limit.")
        }
        return [CapVerification(capID: Self.hardLimitCapID, status: status, checkedAt: now)]
    }
}
