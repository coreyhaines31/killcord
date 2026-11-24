// Together AI spend this month, from the beta billing usage report.
// Reference: https://docs.together.ai/reference/billing-usage
//
// GET https://api.together.ai/v1/billing/usage?month=YYYY-MM&granularity=day&limit=1000[&after=<cursor>]
//   headers: Authorization: Bearer <API key>
//   200:     { "object": "list", "organization_id": "…", "billing_period": "2026-11", "currency": "USD",
//              "data": [{ "date": "2026-11-14", "start_time": "…", "end_time": "…",
//                         "line_items": [{ "product_name": "…", "quantity": "…", "unit_price": "…", "cost": "1.25",
//                                          … }] }],
//              "next_cursor": null }
// `cost` is a decimal string in USD. Daily windows are finalized "through the end of yesterday", so there's no today.
// "This endpoint is in beta and is enabled per organization … Calls from an organization without access return a
// 404." Any project's key reads the whole organization. Errors: { "error": { "message", "type", "param", "code" } }.
import Foundation

public struct TogetherProvider: SpendProvider {
    public let id = ProviderID.together
    static let usageURL = URL(string: "https://api.together.ai/v1/billing/usage")!
    /// More pages than a month of daily windows can need.
    static let maxPages = 5

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from a project in the organization you "
            + "want to watch.")
    }

    struct Report: Decodable {
        let data: [Window]
        let nextCursor: String?

        enum CodingKeys: String, CodingKey {
            case data
            case nextCursor = "next_cursor"
        }

        struct Window: Decodable {
            let lineItems: [LineItem]

            enum CodingKeys: String, CodingKey {
                case lineItems = "line_items"
            }
        }

        struct LineItem: Decodable {
            let cost: FlexibleDecimal
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let month = window(now).monthKey
        var total = Decimal(0)
        var cursor: String?
        for _ in 0..<Self.maxPages {
            var items = [URLQueryItem(name: "month", value: month), URLQueryItem(name: "granularity", value: "day"),
                         URLQueryItem(name: "limit", value: "1000")]
            if let cursor { items.append(URLQueryItem(name: "after", value: cursor)) }
            let report: Report
            do {
                report = try await api.get(Report.self, Self.usageURL.adding(items),
                                           headers: ["Authorization": "Bearer \(key)"])
            } catch SpendError.rejected(status: 404, _), SpendError.unexpectedStatus(404) {
                throw SpendError.requiresSetup("ask Together support to turn on the billing usage API. It's a "
                    + "beta that Together enables per organization.")
            }
            total += report.data.flatMap(\.lineItems).reduce(Decimal(0)) { $0 + $1.cost.value }
            guard let next = report.nextCursor, !next.isEmpty else {
                return SpendSnapshot(provider: id, today: nil, month: Money(total), fetchedAt: now)
            }
            cursor = next
        }
        // A month of daily windows never needs this many pages; stop rather than loop.
        throw SpendError.unexpectedResponse
    }
}
