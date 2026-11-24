// SerpApi searches left.
// Reference: https://serpapi.com/account-api ("free of charge, and using it will not be counted toward your
// monthly quota")
//
// GET https://serpapi.com/account.json?api_key=<private key>   (the key can only go in the query)
//   200: { "account_id": "…", "api_key": "…", "account_email": "…", "plan_name": "Big Data Plan",
//          "plan_renewal_date": "2026-12-24" | null, "searches_per_month": 30000, "plan_searches_left": 5958,
//          "extra_credits": 0, "total_searches_left": 5958, "this_month_usage": 24042, … }
// The reply echoes the key and the account email; Kill Cord decodes neither. Error text has the query's
// values removed (ProviderErrorDetail). The docs show no error body; SerpApi's other routes use { "error": "…" }.
import Foundation

public struct SerpApiProvider: SpendProvider {
    public let id = ProviderID.serpapi

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the private API key from your SerpApi dashboard.")
    }

    struct Account: Decodable {
        let totalSearchesLeft: FlexibleDecimal
        let searchesPerMonth: FlexibleDecimal?
        let extraCredits: FlexibleDecimal?
        let thisMonthUsage: FlexibleDecimal?
        let planRenewalDate: String?

        enum CodingKeys: String, CodingKey {
            case totalSearchesLeft = "total_searches_left"
            case searchesPerMonth = "searches_per_month"
            case extraCredits = "extra_credits"
            case thisMonthUsage = "this_month_usage"
            case planRenewalDate = "plan_renewal_date"
        }
    }

    /// The key percent-encoded as a whole value, so nothing in it can add another parameter.
    static func accountURL(key: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let value = key.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://serpapi.com/account.json?api_key=\(value)")
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        guard let url = Self.accountURL(key: try credentials.require("apiKey")) else { throw SpendError.notConfigured }
        let account = try await api.get(Account.self, url, headers: [:])
        let renewal = account.planRenewalDate.flatMap(Self.day)
        // Extra credits are in the total but not the plan, so the plan size is a limit only without them.
        let noExtras = (account.extraCredits?.value ?? 0) == 0
        let balance = Balance(remaining: account.totalSearchesLeft.value, unit: .units("searches"),
                              kind: renewal == nil ? .prepaid : .allowance,
                              limit: noExtras ? account.searchesPerMonth?.value : nil,
                              used: account.thisMonthUsage?.value, resetsAt: renewal)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    /// "2026-12-24", read as the start of that day in UTC.
    static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
