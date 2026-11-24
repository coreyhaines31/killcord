// Cartesia credits used this month. Cartesia reports credits used, not money or credits left.
// Reference: https://docs.cartesia.ai/api-reference/usage/credits
// Admin keys: https://docs.cartesia.ai/api-reference/authentication ("credit usage, agent usage, and API key
// metadata" need an admin key; standard keys are rejected).
//
// GET https://api.cartesia.ai/usage/credits?start_ts=<RFC 3339>&end_ts=<RFC 3339>
//   headers: Authorization: Bearer sk_car_admin_…, Cartesia-Version: 2026-08-14 (required)
//   200:     { "data": [{ "start_ts": "2026-01-01T00:00:00.000Z", "end_ts": "…", "credits": 1200 }] }
// With no `interval`, the window is one bucket. `start_ts` rounds down to the UTC day; `end_ts` rounds up.
// Errors (2026-03-01 and later): { "error_code": "…", "title": "…", "message": "…", "request_id": "…" }.
import Foundation

public struct CartesiaProvider: SpendProvider {
    public let id = ProviderID.cartesia
    static let creditsURL = URL(string: "https://api.cartesia.ai/usage/credits")!
    static let version = "2026-08-14"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an admin key (sk_car_admin_…). Standard keys can't "
            + "read credit usage.")
    }

    struct Usage: Decodable {
        let data: [Bucket]

        struct Bucket: Decodable {
            let credits: FlexibleDecimal
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let window = window(now)
        let url = Self.creditsURL.adding([
            URLQueryItem(name: "start_ts", value: ISO8601.string(window.monthStart)),
            URLQueryItem(name: "end_ts", value: ISO8601.string(now))
        ])
        let usage = try await api.get(Usage.self, url, headers: ["Authorization": "Bearer \(key)",
                                                                 "Cartesia-Version": Self.version])
        let credits = usage.data.reduce(Decimal(0)) { $0 + $1.credits.value }
        let metric = UsageMetric(id: "credits", name: "Credits used", value: credits, unit: "credits")
        return SpendSnapshot(provider: id, today: nil, month: nil, usage: [metric], fetchedAt: now)
    }
}
