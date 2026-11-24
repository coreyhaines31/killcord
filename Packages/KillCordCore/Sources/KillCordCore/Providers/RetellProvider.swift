// Retell AI call spend today and this month, added up from the call list. Retell has no balance or spend endpoint.
// Reference: https://docs.retellai.com/api-references/list-calls (it "supersedes the legacy GET /list-calls")
// Keys: https://docs.retellai.com/accounts/manage-api-keys ("a key that only pulls call history needs just
// History → Read"). Billing: https://docs.retellai.com/accounts/billing
//
// POST https://api.retellai.com/v3/list-calls
//   headers: Authorization: Bearer <API key>, Content-Type: application/json
//   body:    { "filter_criteria": { "start_timestamp": { "type": "range", "op": "bt", "value": [<ms>, <ms>] } },
//              "sort_order": "descending", "limit": 1000, "pagination_key": "…" }
//   200:     { "items": [{ "start_timestamp": 1794700800000, "call_cost": { "combined_cost": 70, … }, … }],
//              "has_more": true, "pagination_key": "…" }
// `combined_cost` is "in cents". `call_cost` is there once a call has ended. This counts calls only, not chats or
// subscription items such as phone numbers. Errors: { "status": "error", "message": "…" }.
import Foundation

public struct RetellProvider: SpendProvider {
    public let id = ProviderID.retell
    static let listURL = URL(string: "https://api.retellai.com/v3/list-calls")!
    /// 20,000 calls a month. Past that, the reading says it's partial rather than paging on.
    static let maxPages = 20
    static let pageSize = 1000

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Give the key the History › Read permission.")
    }

    struct Page: Decodable {
        let items: [Call]
        let hasMore: Bool
        let paginationKey: String?

        enum CodingKeys: String, CodingKey {
            case items
            case hasMore = "has_more"
            case paginationKey = "pagination_key"
        }

        struct Call: Decodable {
            let startTimestamp: FlexibleDecimal?
            let callCost: Cost?

            enum CodingKeys: String, CodingKey {
                case startTimestamp = "start_timestamp"
                case callCost = "call_cost"
            }
        }

        struct Cost: Decodable {
            let combinedCost: FlexibleDecimal

            enum CodingKeys: String, CodingKey {
                case combinedCost = "combined_cost"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    static func milliseconds(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let window = window(now)
        let dayStart = Decimal(Self.milliseconds(window.dayStart))
        var monthCents = Decimal(0)
        var todayCents = Decimal(0)
        var cursor: String?
        for _ in 0..<Self.maxPages {
            var body: [String: Any] = [
                "filter_criteria": ["start_timestamp": [
                    "type": "range", "op": "bt",
                    "value": [Self.milliseconds(window.monthStart), Self.milliseconds(now)]
                ]],
                "sort_order": "descending", "limit": Self.pageSize
            ]
            if let cursor { body["pagination_key"] = cursor }
            let request = HTTPRequest(method: .post, url: Self.listURL,
                                      headers: ["Authorization": "Bearer \(key)", "Content-Type": "application/json"],
                                      body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
            let page = try api.decode(Page.self, from: try await api.send(request))
            for call in page.items {
                guard let cents = call.callCost?.combinedCost.value else { continue }
                monthCents += cents
                if let start = call.startTimestamp?.value, start >= dayStart { todayCents += cents }
            }
            guard page.hasMore, let next = page.paginationKey, !next.isEmpty else {
                return SpendSnapshot(provider: id, today: Money(todayCents / 100), month: Money(monthCents / 100),
                                     fetchedAt: now)
            }
            cursor = next
        }
        // More calls than Kill Cord pages through. Newest first, so today is complete; the month is a floor, so
        // the reading is labeled.
        return SpendSnapshot(provider: id, today: Money(todayCents / 100), month: Money(monthCents / 100),
                             isEstimate: true, fetchedAt: now)
    }
}
