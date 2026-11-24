// Vapi call spend today and this month, summed by Vapi's analytics query.
// Reference: https://docs.vapi.ai/api-reference/analytics/get (OpenAPI: https://api.vapi.ai/api-json)
// Call cost: the Call schema's `cost` is "the cost of the call in USD".
// Keys: https://docs.vapi.ai/security-and-privacy/api-keys
//
// POST https://api.vapi.ai/analytics
//   headers: Authorization: Bearer <private key>, Content-Type: application/json
//   body:    { "queries": [{ "table": "call", "name": "killcord-spend",
//                            "operations": [{ "operation": "sum", "column": "cost", "alias": "cost" }],
//                            "timeRange": { "step": "day", "start": "<ISO 8601>", "end": "<ISO 8601>",
//                                           "timezone": "UTC" } }] }
//   200/201: [{ "name": "killcord-spend", "timeRange": { … }, "result": [{ "date": "2026-11-14…", "cost": 1.25 }] }]
// The docs give the default result key two ways (`sumcost`, camelCase `sumCost`), so the query sets `alias`.
// The query reads only; it counts calls, not other billable usage.
import Foundation

public struct VapiProvider: SpendProvider {
    public let id = ProviderID.vapi
    static let analyticsURL = URL(string: "https://api.vapi.ai/analytics")!
    static let queryName = "killcord-spend"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a private API key. Public keys are for client "
            + "SDKs.")
    }

    struct Answer: Decodable {
        let name: String
        let result: [Row]

        struct Row: Decodable {
            let date: String?
            let cost: FlexibleDecimal?
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let window = window(now)
        let query: [String: Any] = [
            "table": "call", "name": Self.queryName,
            "operations": [["operation": "sum", "column": "cost", "alias": "cost"]],
            "timeRange": ["step": "day", "start": ISO8601.string(window.monthStart), "end": ISO8601.string(now),
                          "timezone": "UTC"]
        ]
        let body = try JSONSerialization.data(withJSONObject: ["queries": [query]], options: [.sortedKeys])
        let request = HTTPRequest(method: .post, url: Self.analyticsURL,
                                  headers: ["Authorization": "Bearer \(key)", "Content-Type": "application/json"],
                                  body: body)
        let answers = try api.decode([Answer].self, from: try await api.send(request))
        guard let answer = answers.first(where: { $0.name == Self.queryName }) else {
            throw SpendError.unexpectedResponse
        }
        var month = Decimal(0)
        var today = Decimal(0)
        for row in answer.result {
            let cost = row.cost?.value ?? 0
            month += cost
            if row.date.map({ String($0.prefix(10)) }) == window.dayKey { today += cost }
        }
        return SpendSnapshot(provider: id, today: Money(today), month: Money(month), fetchedAt: now)
    }
}
