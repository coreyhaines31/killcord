// Anthropic Usage and Cost Analytics API (beta), and the Admin API lists that name its units.
// Guide:     https://platform.claude.com/docs/en/manage-claude/usage-cost-analytics-api
// Cost:      https://platform.claude.com/docs/en/api/beta/organization/analytics/cost/list
// Usage:     https://platform.claude.com/docs/en/api/beta/organization/analytics/usage/list
// Users:     https://platform.claude.com/docs/en/api/admin/users/list
// API keys:  https://platform.claude.com/docs/en/api/admin/api_keys/list
// Workspaces: https://platform.claude.com/docs/en/api/admin/workspaces/list
// Read 2026-11-17.
//
// GET https://api.anthropic.com/v1/organizations/analytics/cost (and /usage)
//   headers: x-api-key, anthropic-version (the docs' examples send 2026-10-21),
//            anthropic-beta: analytics-usage-cost-2026-08-24 (required)
//   query:   starting_at (RFC 3339, inclusive; on or after 2026-01-01 and within the last 365 days),
//            ending_at (exclusive; required with time_bucket_width; at most 31 days after starting_at),
//            time_bucket_width=1d, group_by[] (up to five of actor, api_key_id, workspace_id, model, …),
//            order_by=time, order=asc, limit (1 to 1000 rows), page (the previous response's next_page)
//   200:     { data: [{ starting_at, ending_at, group: { actor, api_key_id, workspace_id, model, … (null unless
//              grouped) }, cost: { amount, list_amount, currency: "USD", requests } }], has_more, next_page,
//              data_refreshed_at }
//            /usage rows carry usage: { uncached_input_tokens, cache_creation: { ephemeral_1h_input_tokens,
//              ephemeral_5m_input_tokens }, cache_read_input_tokens, output_tokens, requests, … } instead of cost.
//   410:     the cursor expired after a data refresh; pagination restarts from the first page.
// `amount` is the cost after discounts and before credits, a decimal string in cents with six decimal places
// ("41280.000000" is $412.80). Rows with no value for a grouped dimension come back with null, and "every
// combination that has usage or cost appears exactly once", so grouped rows sum to the ungrouped total; Kill
// Cord fetches both and the report says whether they reconcile. Data typically refreshes within 4 hours and
// can take 24; values can change until about 7 days after the month ends.
//
// `actor` is one of: { type: "user_actor", user_id, email_address, name, deleted },
// { type: "service_account_actor", service_account_id }, { type: "federated_actor", provider: { type, … },
// subject }, or { type: "api_actor", api_key_id } (legacy workspace keys, which have no identity). Null when the
// usage has no attributable identity.
//
// Admin lists (GET /v1/organizations/users, /api_keys, /workspaces): after_id paging with limit up to 1000,
// { data, has_more, first_id, last_id }. API keys carry name, partial_key_hint ("sk-ant-api03-R2D...igAA"),
// principal (user_actor or service_account_actor), scope (organization, or workspace with workspace_id),
// status (active, archived, expired, inactive), expires_at. Kill Cord keeps only the hint's last four characters.
//
// Keys: an Admin API key (Console), or a key with read:analytics (Claude Enterprise). There's no read-only key
// for a Console organization. Not available to claude.ai Team plan organizations.
import Foundation

public struct AnthropicAnalyticsProvider: Sendable {
    static let base = URL(string: "https://api.anthropic.com/v1/organizations")!
    static let version = "2026-10-21"
    static let beta = "analytics-usage-cost-2026-08-24"
    /// "starting_at must be on or after January 1, 2026, and within the last 365 days."
    static let earliestData = ISO8601.date("2026-01-01T00:00:00Z")!
    static let lookbackDays = 365
    static let maxWindowDays = 31
    static let pageLimit = 1000
    static let maxPages = 200

    public enum Dimension: String, Sendable, CaseIterable {
        case actor
        case apiKey = "api_key_id"
        case workspace = "workspace_id"

        var attribution: AttributionDimension {
            switch self {
            case .actor: .actor
            case .apiKey: .apiKey
            case .workspace: .workspace
            }
        }
    }

    private let http: HTTPClient
    private let missingScopeHint = "Use an Admin API key from the Claude Console, or a Claude Enterprise key "
        + "with the read:analytics scope."

    public init(http: HTTPClient) {
        self.http = http
    }

    // MARK: Cost and usage

    /// Cost for a range, by one dimension (and optionally by model), with Anthropic's own total for the range.
    public func costReport(_ credentials: ProviderCredentials, by dimension: Dimension, from start: Date,
                           to end: Date, byModel: Bool = false, now: Date) async throws -> AttributionReport {
        let key = try credentials.require("apiKey")
        let range = try checkedRange(from: start, to: end, now: now)
        var rows: [AttributedSpend] = []
        var total = MoneyTotals()
        var units: [AttributionUnitRef: AttributionUnit] = [:]
        var refreshed: [Date] = []
        for window in AttributionWindows.split(start: range.start, end: range.end, maxDays: Self.maxWindowDays) {
            let grouped = try await allRows(CostRow.self, "analytics/cost", window: window,
                                            groupBy: [dimension.rawValue] + (byModel ? ["model"] : []), key: key)
            refreshed += grouped.refreshed
            for row in grouped.rows {
                let unit = unit(for: row.group, dimension)
                if let unit { units[unit.ref] = units[unit.ref] ?? unit }
                rows.append(AttributedSpend(bucketStart: row.start, bucketEnd: row.end, unit: unit?.ref,
                                            model: byModel ? row.group.model : nil, amount: try row.cost.money()))
            }
            let ungrouped = try await allRows(CostRow.self, "analytics/cost", window: window, groupBy: [], key: key)
            refreshed += ungrouped.refreshed
            for row in ungrouped.rows { total.add(try row.cost.money()) }
        }
        return AttributionReport(provider: .anthropic, dimension: dimension.attribution, rangeStart: range.start,
                                 rangeEnd: range.end, rows: rows, providerTotal: total,
                                 dataRefreshedAt: refreshed.min(), meaningVerified: true,
                                 units: units.values.sorted { $0.ref < $1.ref })
    }

    /// Token and request counts for a range, by one dimension (and optionally by model).
    public func usage(_ credentials: ProviderCredentials, by dimension: Dimension, from start: Date, to end: Date,
                      byModel: Bool = false, now: Date) async throws -> [AttributedUsage] {
        let key = try credentials.require("apiKey")
        let range = try checkedRange(from: start, to: end, now: now)
        var result: [AttributedUsage] = []
        for window in AttributionWindows.split(start: range.start, end: range.end, maxDays: Self.maxWindowDays) {
            let page = try await allRows(UsageRow.self, "analytics/usage", window: window,
                                         groupBy: [dimension.rawValue] + (byModel ? ["model"] : []), key: key)
            for row in page.rows {
                let usage = row.usage
                let cacheWrites = (usage.cacheCreation?.ephemeral1h ?? 0) + (usage.cacheCreation?.ephemeral5m ?? 0)
                let cacheReads = usage.cacheRead ?? 0
                result.append(AttributedUsage(
                    bucketStart: row.start, bucketEnd: row.end, unit: unit(for: row.group, dimension)?.ref,
                    model: byModel ? row.group.model : nil,
                    inputTokens: (usage.uncachedInput ?? 0) + cacheWrites + cacheReads,
                    cachedInputTokens: cacheReads, outputTokens: usage.output ?? 0, requests: usage.requests))
            }
        }
        return result
    }

    /// Whole UTC days from `start` up to and including today (partial), within Anthropic's history.
    func checkedRange(from start: Date, to end: Date, now: Date) throws -> DateInterval {
        let tomorrow = AttributionWindows.utcDayStart(now).addingTimeInterval(86_400)
        let lower = AttributionWindows.utcDayStart(start)
        let upper = min(AttributionWindows.utcDayStart(end.addingTimeInterval(86_399)), tomorrow)
        let lookback = -Double(Self.lookbackDays - 1) * 86_400
        let oldestAllowed = max(Self.earliestData, AttributionWindows.utcDayStart(now).addingTimeInterval(lookback))
        guard lower >= oldestAllowed else { throw AttributionRangeError.beforeEarliest(oldestAllowed) }
        guard upper > lower else { throw AttributionRangeError.empty }
        return DateInterval(start: lower, end: upper)
    }

    private func unit(for group: Group, _ dimension: Dimension) -> AttributionUnit? {
        switch dimension {
        case .apiKey:
            return group.apiKeyID.map { AttributionUnit(provider: .anthropic, kind: .apiKey, externalID: $0) }
        case .workspace:
            return group.workspaceID.map { AttributionUnit(provider: .anthropic, kind: .workspace, externalID: $0) }
        case .actor:
            return group.actor?.unit
        }
    }

    private func headers(_ key: String, beta: Bool) -> [String: String] {
        var headers = ["x-api-key": key, "anthropic-version": Self.version, "accept": "application/json"]
        if beta { headers["anthropic-beta"] = Self.beta }
        return headers
    }

    /// Every row for one window, following next_page. A 410 (cursor expired after a refresh) restarts once.
    private func allRows<Row: Decodable & Sendable>(_ type: Row.Type, _ path: String, window: DateInterval,
                                                    groupBy: [String], key: String) async throws
        -> (rows: [Row], refreshed: [Date]) {
        restart: for attempt in 0..<2 {
            var rows: [Row] = []
            var refreshed: [Date] = []
            var page: String?
            for _ in 0..<Self.maxPages {
                var items = [
                    URLQueryItem(name: "starting_at", value: ISO8601.string(window.start)),
                    URLQueryItem(name: "ending_at", value: ISO8601.string(window.end)),
                    URLQueryItem(name: "time_bucket_width", value: "1d"),
                    URLQueryItem(name: "order_by", value: "time"),
                    URLQueryItem(name: "order", value: "asc"),
                    URLQueryItem(name: "limit", value: String(Self.pageLimit))
                ]
                items += groupBy.map { URLQueryItem(name: "group_by[]", value: $0) }
                if let page { items.append(URLQueryItem(name: "page", value: page)) }
                let request = HTTPRequest(url: Self.base.appendingPathComponent(path).adding(items),
                                          headers: headers(key, beta: true))
                guard let response = try await send(request, allowGone: attempt == 0) else { continue restart }
                let body = try decode(Page<Row>.self, response)
                rows += body.data
                if let date = body.dataRefreshedAt.flatMap(ISO8601.date) { refreshed.append(date) }
                guard body.hasMore, let next = body.nextPage else { return (rows, refreshed) }
                page = next
            }
            throw SpendError.unexpectedResponse
        }
        throw SpendError.unexpectedResponse
    }

    /// Nil only for a 410 when a restart is allowed. Error text never includes a header value (the key).
    private func send(_ request: HTTPRequest, allowGone: Bool = false) async throws -> HTTPResponse? {
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch let error as SpendError {
            throw error
        } catch {
            throw SpendError.network
        }
        if response.status == 410, allowGone { return nil }
        guard (200..<300).contains(response.status) else {
            throw SpendError.from(status: response.status, headers: response.headers, missingScopeHint: missingScopeHint,
                                  detail: ProviderErrorDetail.message(in: response.body, sentWith: request))
        }
        return response
    }

    private func decode<T: Decodable>(_ type: T.Type, _ response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw SpendError.unexpectedResponse
        }
    }

    // MARK: Admin lists

    /// Users, workspaces (archived and default included) and API keys, as attribution units. Each key carries
    /// its owner's email when it acts as a user.
    public func units(_ credentials: ProviderCredentials) async throws -> [AttributionUnit] {
        let key = try credentials.require("apiKey")
        let users = try await list(UserItem.self, "users", extra: [], key: key)
        let workspaces = try await list(WorkspaceItem.self, "workspaces",
                                        extra: [URLQueryItem(name: "include_archived", value: "true"),
                                                URLQueryItem(name: "include_default", value: "true")], key: key)
        let keys = try await list(APIKeyItem.self, "api_keys", extra: [], key: key)
        let emails = Dictionary(users.map { ($0.id, $0.email) }) { first, _ in first }
        return users.map {
            AttributionUnit(provider: .anthropic, kind: .user, externalID: $0.id, label: $0.name, ownerEmail: $0.email,
                            status: $0.role)
        } + workspaces.map {
            AttributionUnit(provider: .anthropic, kind: .workspace, externalID: $0.id, label: $0.name,
                            status: $0.archivedAt == nil ? "active" : "archived")
        } + keys.map {
            AttributionUnit(provider: .anthropic, kind: .apiKey, externalID: $0.id, label: $0.name,
                            keyHint: AttributionUnit.keyHint(fromRedacted: $0.partialKeyHint),
                            ownerEmail: $0.principal?.userID.flatMap { emails[$0] },
                            parentID: $0.scope?.workspaceID, status: $0.status,
                            expiresAt: $0.expiresAt.flatMap(ISO8601.date))
        }
    }

    private func list<Item: Decodable & Sendable>(_ type: Item.Type, _ path: String, extra: [URLQueryItem],
                                                  key: String) async throws -> [Item] {
        var items: [Item] = []
        var after: String?
        for _ in 0..<Self.maxPages {
            var query = [URLQueryItem(name: "limit", value: String(Self.pageLimit))] + extra
            if let after { query.append(URLQueryItem(name: "after_id", value: after)) }
            let request = HTTPRequest(url: Self.base.appendingPathComponent(path).adding(query),
                                      headers: headers(key, beta: false))
            guard let response = try await send(request) else { throw SpendError.unexpectedResponse }
            let page = try decode(ListPage<Item>.self, response)
            items += page.data
            guard page.hasMore, let last = page.lastID else { return items }
            after = last
        }
        throw SpendError.unexpectedResponse
    }
}
