// OpenAI Administration API: costs and completions usage by project, user or API key, and project key owners.
// Reference pages, under
// https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/
//   Costs:    usage/methods/costs/
//   Usage:    usage/methods/completions
//   Projects: projects/methods/list
//   Keys:     projects/subresources/api_keys/methods/list
// Read 2026-11-17.
//
// GET https://api.openai.com/v1/organization/costs
//   headers: Authorization: Bearer <Admin API key>
//   query:   start_time (Unix seconds, inclusive, required), end_time (exclusive), bucket_width=1d (the only
//            width), group_by (project_id, user_id, line_item, api_key_id, api_source), limit (1 to 180
//            buckets), page (the previous response's next_page)
//   200:     { object: "page", data: [{ object: "bucket", start_time, end_time, results: [{ object:
//              "organization.costs.result", amount: { value, currency: "usd" }, project_id, user_id, api_key_id,
//              line_item, … (null unless grouped) }] }], has_more, next_page }
// "Support for combining user_id with project_id grouping or the project_ids filter depends on the
// organization and requested time range. Unsupported combinations return HTTP 400." Kill Cord groups by one
// dimension per request. Freshness is not documented.
//
// GET https://api.openai.com/v1/organization/usage/completions: the same paging; bucket_width 1m, 1h or 1d
// (1d allows up to 31 buckets per page); results carry input_tokens (including cached), input_cached_tokens,
// output_tokens, num_model_requests and the grouped project_id, user_id, api_key_id, model.
//
// GET /v1/organization/projects and /v1/organization/projects/{id}/api_keys: { object: "list", data, first_id,
// last_id, has_more }, paged with after and limit (1 to 100). A key has name, redacted_value, created_at,
// last_used_at, expires_at, and owner: { type: "user" | "service_account", user: { id, email, name, role } |
// service_account: { id, name, role } }.
//
// UNVERIFIED:
// - What `user_id` identifies. The reference says only "the user ID of the grouped costs result". Reports
//   grouped by user set `meaningVerified = false`; the spec (teams-spec.md section 3) says to check it against a
//   real organization before showing it as a person.
// - How array query parameters are spelled. Neither curl example on the reference uses one; Kill Cord sends a
//   repeated `group_by=` (the form OpenAI's cookbook produces). Check on a real organization.
// - `amount.value` is a number in the currency's major unit, read straight into Decimal (as OpenAIProvider does).
import Foundation

public struct OpenAIAttributionProvider: Sendable {
    static let base = URL(string: "https://api.openai.com/v1/organization")!
    static let costPageLimit = 180
    static let usagePageLimit = 31
    static let listLimit = 100
    static let maxPages = 200

    public enum Dimension: String, Sendable, CaseIterable {
        case project = "project_id"
        case user = "user_id"
        case apiKey = "api_key_id"

        var attribution: AttributionDimension {
            switch self {
            case .project: .project
            case .user: .user
            case .apiKey: .apiKey
            }
        }

        var unitKind: AttributionUnitKind {
            switch self {
            case .project: .project
            case .user: .user
            case .apiKey: .apiKey
            }
        }

        /// See UNVERIFIED in the file header.
        var meaningVerified: Bool { self != .user }
    }

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an Admin API key from Settings › Organization › "
            + "Admin keys, with read access to usage.")
    }

    private func headers(_ key: String) -> [String: String] {
        ["Authorization": "Bearer \(key)", "accept": "application/json"]
    }

    /// Cost for whole UTC days, by one dimension, with OpenAI's own total for the same days.
    public func costReport(_ credentials: ProviderCredentials, by dimension: Dimension, from start: Date,
                           to end: Date, now: Date) async throws -> AttributionReport {
        let key = try credentials.require("apiKey")
        let range = try checkedRange(from: start, to: end, now: now)
        var rows: [AttributedSpend] = []
        for bucket in try await buckets(CostResult.self, BucketQuery(
            path: "costs", range: range, groupBy: dimension.rawValue, limit: Self.costPageLimit), key: key) {
            for result in bucket.results {
                let unit = result.id(for: dimension).map {
                    AttributionUnitRef(kind: dimension.unitKind, externalID: $0)
                }
                rows.append(AttributedSpend(bucketStart: bucket.start, bucketEnd: bucket.end, unit: unit,
                                            amount: result.amount.money))
            }
        }
        var total = MoneyTotals()
        for bucket in try await buckets(CostResult.self, BucketQuery(
            path: "costs", range: range, groupBy: nil, limit: Self.costPageLimit), key: key) {
            for result in bucket.results { total.add(result.amount.money) }
        }
        return AttributionReport(provider: .openai, dimension: dimension.attribution, rangeStart: range.start,
                                 rangeEnd: range.end, rows: rows, providerTotal: total, dataRefreshedAt: nil,
                                 meaningVerified: dimension.meaningVerified)
    }

    /// Completions token and request counts for whole UTC days, by one dimension.
    public func usage(_ credentials: ProviderCredentials, by dimension: Dimension, from start: Date, to end: Date,
                      now: Date) async throws -> [AttributedUsage] {
        let key = try credentials.require("apiKey")
        let range = try checkedRange(from: start, to: end, now: now)
        return try await buckets(UsageResult.self, BucketQuery(
            path: "usage/completions", range: range, groupBy: dimension.rawValue, limit: Self.usagePageLimit),
                                 key: key).flatMap { bucket in
            bucket.results.map { result in
                AttributedUsage(bucketStart: bucket.start, bucketEnd: bucket.end,
                                unit: result.id(for: dimension).map {
                                    AttributionUnitRef(kind: dimension.unitKind, externalID: $0)
                                },
                                inputTokens: result.inputTokens ?? 0, cachedInputTokens: result.inputCachedTokens ?? 0,
                                outputTokens: result.outputTokens ?? 0, requests: result.numModelRequests)
            }
        }
    }

    func checkedRange(from start: Date, to end: Date, now: Date) throws -> DateInterval {
        let tomorrow = AttributionWindows.utcDayStart(now).addingTimeInterval(86_400)
        let lower = AttributionWindows.utcDayStart(start)
        let upper = min(AttributionWindows.utcDayStart(end.addingTimeInterval(86_399)), tomorrow)
        guard upper > lower else { throw AttributionRangeError.empty }
        return DateInterval(start: lower, end: upper)
    }

    struct BucketQuery {
        let path: String
        let range: DateInterval
        let groupBy: String?
        let limit: Int
    }

    private func buckets<Result: Decodable & Sendable>(_ type: Result.Type, _ query: BucketQuery,
                                                       key: String) async throws -> [Bucket<Result>] {
        let (path, range, groupBy, limit) = (query.path, query.range, query.groupBy, query.limit)
        var buckets: [Bucket<Result>] = []
        var page: String?
        for _ in 0..<Self.maxPages {
            var items = [
                URLQueryItem(name: "start_time", value: String(Int(range.start.timeIntervalSince1970))),
                URLQueryItem(name: "end_time", value: String(Int(range.end.timeIntervalSince1970))),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: String(limit))
            ]
            if let groupBy { items.append(URLQueryItem(name: "group_by", value: groupBy)) }
            if let page { items.append(URLQueryItem(name: "page", value: page)) }
            let body = try await api.get(Page<Result>.self, Self.base.appendingPathComponent(path).adding(items),
                                         headers: headers(key))
            buckets += body.data
            guard body.hasMore == true, let next = body.nextPage else { return buckets }
            page = next
        }
        throw SpendError.unexpectedResponse
    }

    // MARK: Units

    /// Projects (archived included) and every project's API keys, with each key's owner.
    public func units(_ credentials: ProviderCredentials) async throws -> [AttributionUnit] {
        let key = try credentials.require("apiKey")
        let projects = try await list(Project.self, "projects",
                                      extra: [URLQueryItem(name: "include_archived", value: "true")], key: key)
        var units = projects.map {
            AttributionUnit(provider: .openai, kind: .project, externalID: $0.id, label: $0.name, status: $0.status)
        }
        for project in projects {
            let keys = try await list(ProjectKey.self, "projects/\(project.id)/api_keys", extra: [], key: key)
            units += keys.map { item in
                AttributionUnit(provider: .openai, kind: .apiKey, externalID: item.id, label: item.name,
                                keyHint: AttributionUnit.keyHint(fromRedacted: item.redactedValue),
                                ownerEmail: item.owner?.user?.email, parentID: project.id,
                                expiresAt: item.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) })
            }
        }
        return units
    }

    private func list<Item: Decodable & Sendable>(_ type: Item.Type, _ path: String, extra: [URLQueryItem],
                                                  key: String) async throws -> [Item] {
        var items: [Item] = []
        var after: String?
        for _ in 0..<Self.maxPages {
            var query = [URLQueryItem(name: "limit", value: String(Self.listLimit))] + extra
            if let after { query.append(URLQueryItem(name: "after", value: after)) }
            let page = try await api.get(ListPage<Item>.self, Self.base.appendingPathComponent(path).adding(query),
                                         headers: headers(key))
            items += page.data
            guard page.hasMore == true, let last = page.lastID else { return items }
            after = last
        }
        throw SpendError.unexpectedResponse
    }
}

// MARK: Wire shapes

extension OpenAIAttributionProvider {
    struct Page<Result: Decodable & Sendable>: Decodable, Sendable {
        let data: [Bucket<Result>]
        let hasMore: Bool?
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    struct Bucket<Result: Decodable & Sendable>: Decodable, Sendable {
        let startTime: Int
        let endTime: Int
        let results: [Result]

        var start: Date { Date(timeIntervalSince1970: TimeInterval(startTime)) }
        var end: Date { Date(timeIntervalSince1970: TimeInterval(endTime)) }

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case endTime = "end_time"
            case results
        }
    }

    struct Grouping: Decodable, Sendable {
        let projectID: String?
        let userID: String?
        let apiKeyID: String?

        enum CodingKeys: String, CodingKey {
            case projectID = "project_id"
            case userID = "user_id"
            case apiKeyID = "api_key_id"
        }
    }

    struct CostAmount: Decodable, Sendable {
        let value: FlexibleDecimal
        let currency: String

        var money: Money { Money(value.value, Currency(currency)) }
    }

    struct CostResult: Decodable, Sendable {
        let amount: CostAmount
        let grouping: Grouping

        init(from decoder: Decoder) throws {
            amount = try decoder.container(keyedBy: CodingKeys.self).decode(CostAmount.self, forKey: .amount)
            grouping = try Grouping(from: decoder)
        }

        enum CodingKeys: String, CodingKey { case amount }

        func id(for dimension: Dimension) -> String? { grouping.id(for: dimension) }
    }

    struct UsageResult: Decodable, Sendable {
        let inputTokens: Int?
        let inputCachedTokens: Int?
        let outputTokens: Int?
        let numModelRequests: Int?
        let grouping: Grouping

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case inputCachedTokens = "input_cached_tokens"
            case outputTokens = "output_tokens"
            case numModelRequests = "num_model_requests"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
            inputCachedTokens = try container.decodeIfPresent(Int.self, forKey: .inputCachedTokens)
            outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
            numModelRequests = try container.decodeIfPresent(Int.self, forKey: .numModelRequests)
            grouping = try Grouping(from: decoder)
        }

        func id(for dimension: Dimension) -> String? { grouping.id(for: dimension) }
    }

    struct ListPage<Item: Decodable & Sendable>: Decodable, Sendable {
        let data: [Item]
        let hasMore: Bool?
        let lastID: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case lastID = "last_id"
        }
    }

    struct Project: Decodable, Sendable {
        let id: String
        let name: String?
        let status: String?
    }

    struct ProjectKey: Decodable, Sendable {
        let id: String
        let name: String?
        let redactedValue: String?
        let expiresAt: Int?
        let owner: Owner?

        struct Owner: Decodable, Sendable {
            let type: String
            let user: OwnerUser?
        }

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case redactedValue = "redacted_value"
            case expiresAt = "expires_at"
            case owner
        }
    }

    struct OwnerUser: Decodable, Sendable {
        let id: String
        let email: String?
    }
}

extension OpenAIAttributionProvider.Grouping {
    func id(for dimension: OpenAIAttributionProvider.Dimension) -> String? {
        switch dimension {
        case .project: projectID
        case .user: userID
        case .apiKey: apiKeyID
        }
    }
}
