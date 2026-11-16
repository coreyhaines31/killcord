// Neon API, consumption history (v2) and the organization spending threshold.
// Consumption: https://neon.com/docs/guides/consumption-metrics
// Usage and pricing: https://neon.com/docs/introduction/usage-calculations
// Spending threshold: https://neon.com/docs/introduction/spending-limit
// API keys: https://neon.com/docs/manage/api-keys
//
// GET https://console.neon.tech/api/v2/consumption_history/v2/projects
//   headers: Authorization: Bearer <API key>
//   query:   from, to (RFC 3339), granularity=daily (last 60 days), org_id, metrics (comma-separated),
//            limit (1 to 100 projects), cursor (pass back unchanged for the next page)
//   200:     { projects: [{ project_id, periods: [{ consumption: [{ timeframe_start, timeframe_end,
//              metrics: [{ metric_name: "compute_unit_seconds", value: 84 }] }] }] }], pagination: { cursor } }
// Neon reports usage, never dollars. Plans: Launch, Scale, Agent, Enterprise (others get 403). Data updates
// about every 15 minutes; Neon asks not to poll more often. Zero-valued metrics may be left out.
//
// GET https://console.neon.tech/api/v2/organizations/{org_id}/billing/spending_limit   (beta)
//   200: { "spending_limit_cents": 50000 } or { "spending_limit_cents": null }
// The threshold emails admins at 80% and 100%; it doesn't stop usage.
import Foundation

public struct NeonProvider: SpendProvider {
    public let id = ProviderID.neon
    static let base = URL(string: "https://console.neon.tech/api/v2/")!
    static let pageSize = 100
    public static let thresholdCapID = "neon.spending-threshold"

    // The metrics Kill Cord shows, with how to turn Neon's raw unit into a readable one.
    // Named fields describe the provider metric conversion table.
    // swiftlint:disable:next large_tuple
    static let metrics: [(id: String, name: String, unit: String, divisor: Decimal)] = [
        ("compute_unit_seconds", "Compute", "CU-hours", 3600),
        ("root_branch_bytes_month", "Root branch storage", "GB-months", 1_000_000_000),
        ("child_branch_bytes_month", "Child branch storage", "GB-months", 1_000_000_000),
        ("instant_restore_bytes_month", "Instant restore", "GB-months", 1_000_000_000),
        ("public_network_transfer_bytes", "Public network transfer", "GB", 1_000_000_000)
    ]

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Neon's consumption API needs a Launch, Scale, Agent, or "
            + "Enterprise plan, and a key for the organization.")
    }

    struct Consumption: Decodable {
        struct Project: Decodable {
            let periods: [Period]
        }

        struct Period: Decodable {
            let consumption: [Bucket]
        }

        struct Bucket: Decodable {
            let timeframeStart: String
            let metrics: [Metric]

            enum CodingKeys: String, CodingKey {
                case timeframeStart = "timeframe_start"
                case metrics
            }
        }

        struct Metric: Decodable {
            let metricName: String
            let value: FlexibleDecimal

            enum CodingKeys: String, CodingKey {
                case metricName = "metric_name"
                case value
            }
        }

        struct Pagination: Decodable {
            let cursor: String?
        }

        let projects: [Project]
        let pagination: Pagination?
    }

    struct SpendingLimit: Decodable {
        let spendingLimitCents: Int?

        enum CodingKeys: String, CodingKey {
            case spendingLimitCents = "spending_limit_cents"
        }
    }

    func headers(_ key: String) -> [String: String] {
        ["Authorization": "Bearer \(key)", "accept": "application/json"]
    }

    func consumptionURL(orgID: String, from: Date, to end: Date, cursor: String?) throws -> URL {
        guard FieldFormat.isIdentifier(orgID) else { throw SpendError.notConfigured }
        var items = [
            URLQueryItem(name: "from", value: ISO8601.string(from)),
            URLQueryItem(name: "to", value: ISO8601.string(end)),
            URLQueryItem(name: "granularity", value: "daily"),
            URLQueryItem(name: "org_id", value: orgID),
            URLQueryItem(name: "metrics", value: Self.metrics.map(\.id).joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(Self.pageSize))
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return Self.base.appendingPathComponent("consumption_history/v2/projects").adding(items)
    }

    func send<T: Decodable>(_ type: T.Type, _ url: URL, key: String) async throws -> T {
        do {
            return try await api.get(type, url, headers: headers(key))
        } catch SpendError.missingScope {
            throw SpendError.planNotSupported("Neon's consumption API needs a Launch, Scale, Agent, or Enterprise "
                + "plan, and a key that belongs to the organization.")
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        let key = try credentials.require("apiKey")
        let window = window(now)
        _ = try await send(Consumption.self, try consumptionURL(orgID: try credentials.require("orgID"),
                                                                from: window.dayStart, to: now, cursor: nil), key: key)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let orgID = try credentials.require("orgID")
        let window = window(now)
        var totals: [String: Decimal] = [:]
        var cursor: String?
        for _ in 0..<20 {
            let page = try await send(Consumption.self, try consumptionURL(orgID: orgID, from: window.monthStart,
                                                                           to: now, cursor: cursor), key: key)
            for project in page.projects {
                for period in project.periods {
                    for bucket in period.consumption {
                        for metric in bucket.metrics { totals[metric.metricName, default: 0] += metric.value.value }
                    }
                }
            }
            // A short page is the last one; Neon returns a cursor even then.
            guard page.projects.count >= Self.pageSize, let next = page.pagination?.cursor else { break }
            cursor = next
        }
        let usage = Self.metrics.map { metric in
            UsageMetric(id: metric.id, name: metric.name, value: (totals[metric.id] ?? 0) / metric.divisor,
                        unit: metric.unit)
        }
        return SpendSnapshot(provider: id, today: nil, month: nil, usage: usage, fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let key = credentials["apiKey"], let orgID = credentials["orgID"], FieldFormat.isIdentifier(orgID),
              let limit = try? await api.get(
                SpendingLimit.self,
                Self.base.appendingPathComponent("organizations/\(orgID)/billing/spending_limit"),
                headers: headers(key))
        else { return [] }
        let status: CapVerification.Status
        if let cents = limit.spendingLimitCents, cents > 0 {
            status = .on("Neon reports a spending threshold of \(MoneyText.string(.fromCents(cents))) a month. "
                + "It emails admins; it doesn't stop usage.")
        } else {
            status = .off("Neon reports no spending threshold.")
        }
        return [CapVerification(capID: Self.thresholdCapID, status: status, checkedAt: now)]
    }
}
