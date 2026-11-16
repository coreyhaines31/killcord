// Anthropic Admin API, cost report.
// Docs: https://platform.claude.com/docs/en/manage-claude/usage-cost-api
// Reference: https://platform.claude.com/docs/en/api/admin-api/usage-cost/get-cost-report
// Keys: https://platform.claude.com/docs/en/manage-claude/admin-api-keys
//
// GET https://api.anthropic.com/v1/organizations/cost_report
//   headers: x-api-key: <Admin API key, sk-ant-admin…>, anthropic-version: 2023-06-01
//   query:   starting_at (RFC 3339, required), ending_at, bucket_width=1d (the only width), limit (max 31),
//            page (the previous response's next_page)
//   200:     { data: [{ starting_at, ending_at, results: [{ amount: "123.45", currency: "USD", … }] }],
//              has_more, next_page }
// `amount` is a decimal string in the currency's lowest unit (cents): "123.45" USD is $1.2345. Empty days
// are included with `results: []`. Costs usually appear within 5 minutes. Priority Tier is not included.
// The docs mark this endpoint legacy but supported; the newer analytics endpoint can lag up to 24 hours, so
// the legacy one is the better fit for a glance.
//
// Anthropic has no read-only admin key, and Console organizations can't read spend limits over the API, so
// every Anthropic cap in the audit is self-reported.
import Foundation

public struct AnthropicProvider: SpendProvider {
    public let id = ProviderID.anthropic
    static let base = URL(string: "https://api.anthropic.com/v1/organizations/cost_report")!
    static let version = "2023-06-01"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an Admin API key created by an organization admin, "
            + "not a regular API key.")
    }

    struct Report: Decodable {
        struct Bucket: Decodable {
            let startingAt: String
            let endingAt: String
            let results: [Result]

            enum CodingKeys: String, CodingKey {
                case startingAt = "starting_at"
                case endingAt = "ending_at"
                case results
            }
        }

        struct Result: Decodable {
            let amount: String
            let currency: String?
        }

        let data: [Bucket]
        let hasMore: Bool
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    func headers(_ key: String) -> [String: String] {
        ["x-api-key": key, "anthropic-version": Self.version, "accept": "application/json"]
    }

    func url(from start: Date, to end: Date, limit: Int, page: String?) -> URL {
        var items = [
            URLQueryItem(name: "starting_at", value: ISO8601.string(start)),
            URLQueryItem(name: "ending_at", value: ISO8601.string(end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let page { items.append(URLQueryItem(name: "page", value: page)) }
        return Self.base.adding(items)
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        let key = try credentials.require("apiKey")
        let window = window(now)
        _ = try await api.get(Report.self, url(from: window.dayStart, to: window.dayEnd, limit: 1, page: nil),
                              headers: headers(key))
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let window = window(now)
        var buckets: [Report.Bucket] = []
        var page: String?
        // A month is at most 31 daily buckets, one page; follow next_page anyway, with a ceiling.
        for _ in 0..<6 {
            let report = try await api.get(Report.self, url(from: window.monthStart, to: window.dayEnd,
                                                            limit: 31, page: page), headers: headers(key))
            buckets += report.data
            guard report.hasMore, let next = report.nextPage else { break }
            page = next
        }
        var month = Money.zero()
        var today = Money.zero()
        for bucket in buckets {
            guard let start = ISO8601.date(bucket.startingAt) else { throw SpendError.unexpectedResponse }
            for result in bucket.results {
                let currency = Currency(result.currency ?? "USD")
                guard currency == .usd, let money = Money.fromMinorUnits(result.amount, currency) else {
                    throw SpendError.unexpectedResponse
                }
                month = month + money
                if start >= window.dayStart { today = today + money }
            }
        }
        return SpendSnapshot(provider: id, today: today, month: month, fetchedAt: now)
    }
}
