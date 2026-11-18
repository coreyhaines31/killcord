// Ahrefs API units.
// Reference: https://docs.ahrefs.com/docs/api/subscription-info/operations/get-limits-and-usage
//
// GET https://api.ahrefs.com/v3/subscription-info/limits-and-usage
//   headers: Authorization: Bearer <API key>, Accept: application/json
//   200:     { "limits_and_usage": { "subscription": "…", "usage_reset_date": "…",
//              "units_limit_workspace": 500000 | null, "units_usage_workspace": 120000 | null,
//              "units_limit_api_key": 100000 | null, "units_usage_api_key": 4000, "api_key_expiration_date": "…" } }
// Free: the docs say this call uses no API units. The workspace pool is what the plan bills, so it's shown;
// a null limit means unlimited, which has no balance. Errors: { "error": "…" }.
import Foundation

public struct AhrefsProvider: SpendProvider {
    public let id = ProviderID.ahrefs
    static let limitsURL = URL(string: "https://api.ahrefs.com/v3/subscription-info/limits-and-usage")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Your Ahrefs plan or key may not include API access.")
    }

    struct Response: Decodable {
        let limitsAndUsage: Details

        struct Details: Decodable {
            let unitsLimitWorkspace: FlexibleDecimal?
            let unitsUsageWorkspace: FlexibleDecimal?
            let usageResetDate: String?

            enum CodingKeys: String, CodingKey {
                case unitsLimitWorkspace = "units_limit_workspace"
                case unitsUsageWorkspace = "units_usage_workspace"
                case usageResetDate = "usage_reset_date"
            }
        }

        enum CodingKeys: String, CodingKey {
            case limitsAndUsage = "limits_and_usage"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let details = try await api.get(Response.self, Self.limitsURL,
                                        headers: ["Authorization": "Bearer \(key)", "Accept": "application/json"])
            .limitsAndUsage
        var balance: Balance?
        if let limit = details.unitsLimitWorkspace?.value {
            let used = details.unitsUsageWorkspace?.value ?? 0
            balance = Balance(remaining: max(0, limit - used), unit: .units("API units"), kind: .allowance,
                              limit: limit, used: used, resetsAt: details.usageResetDate.flatMap(Self.date))
        }
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    /// "2026-12-01" or a full ISO 8601 time. The docs type it as a date.
    static func date(_ text: String) -> Date? {
        if let date = ISO8601.date(text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
