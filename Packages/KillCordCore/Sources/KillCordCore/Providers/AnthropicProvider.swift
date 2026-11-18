// Anthropic Admin API, cost report.
// Docs: https://platform.claude.com/docs/en/manage-claude/usage-cost-api
// Reference: https://platform.claude.com/docs/en/api/admin-api/usage-cost/get-cost-report
// Keys: https://platform.claude.com/docs/en/manage-claude/admin-api-keys
//
// GET https://api.anthropic.com/v1/organizations/cost_report
//   headers: x-api-key: <Admin API key, sk-ant-admin…>, anthropic-version: 2023-06-01
//   query:   starting_at (RFC 3339, required), bucket_width=1d (the only width), limit (max 31),
//            page (the previous response's next_page). Kill Cord leaves out ending_at, see below.
//   200:     { data: [{ starting_at, ending_at, results: [{ amount: "123.45", currency: "USD", workspace_id,
//              model, … (null when not grouped) }] }], has_more, next_page }
//   4xx:     { type: "error", error: { type, message } }
// `amount` is a decimal string in the currency's lowest unit (cents): "123.45" USD is $1.2345. Empty days
// are included with `results: []`. Costs usually appear within 5 minutes. Priority Tier is not included.
// The docs mark this endpoint legacy but supported; the newer analytics endpoint can lag up to 24 hours, so
// the legacy one is the better fit for a glance.
//
// Observed against the live API (2026-11-17): it clamps ending_at to the start of the current UTC day, so
// a today-only range (starting_at = today 00:00Z, ending_at = tomorrow or now) is empty and returns HTTP 400
// "Invalid date range: ending date must be after starting date". Kill Cord therefore omits ending_at and
// always starts at or before yesterday 00:00Z, then sums the buckets itself. Today's partial bucket may or
// may not be in the response; when it isn't, today is unreported (nil), not $0.
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

    func url(from start: Date, limit: Int, page: String?) -> URL {
        var items = [
            URLQueryItem(name: "starting_at", value: ISO8601.string(start)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let page { items.append(URLQueryItem(name: "page", value: page)) }
        return Self.base.adding(items)
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        let key = try credentials.require("apiKey")
        _ = try await api.get(Report.self, url(from: yesterdayStart(window(now)), limit: 1, page: nil),
                              headers: headers(key))
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let window = window(now)
        // On the 1st, the month so far is only today, a range the API treats as empty; start a day early.
        let start = min(window.monthStart, yesterdayStart(window))
        var buckets: [Report.Bucket] = []
        var page: String?
        // A month is at most 31 daily buckets, one page; follow next_page anyway, with a ceiling.
        for _ in 0..<6 {
            let report = try await api.get(Report.self, url(from: start, limit: 31, page: page),
                                           headers: headers(key))
            buckets += report.data
            guard report.hasMore, let next = report.nextPage else { break }
            page = next
        }
        var month = Money.zero()
        var today: Money?
        for bucket in buckets {
            guard let start = ISO8601.date(bucket.startingAt) else { throw SpendError.unexpectedResponse }
            guard start >= window.monthStart else { continue }
            if start >= window.dayStart, today == nil { today = .zero() }
            for result in bucket.results {
                let currency = Currency(result.currency ?? "USD")
                guard currency == .usd, let money = Money.fromMinorUnits(result.amount, currency) else {
                    throw SpendError.unexpectedResponse
                }
                month += money
                if start >= window.dayStart { today? += money }
            }
        }
        // Without today's bucket the month runs only through the start of today; say so.
        return SpendSnapshot(provider: id, today: today, month: month,
                             dataAsOf: today == nil ? window.dayStart : nil, fetchedAt: now)
    }

    func yesterdayStart(_ window: BillingWindow) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = window.timeZone
        return calendar.date(byAdding: .day, value: -1, to: window.dayStart)!
    }
}
