// ScrapingBee plan credits.
// Reference: https://www.scrapingbee.com/documentation/ ("Usage endpoint")
//
// GET https://app.scrapingbee.com/api/v1/usage
//   headers: Authorization: Bearer <API key>   (the api_key query parameter is deprecated)
//   200:     { "max_api_credit": 20000000, "used_api_credit": 3704332, "max_concurrency": 200,
//              "current_concurrency": 1, "renewal_subscription_date": "2022-04-18T10:05:58.134716" }
// Credits are integers. The renewal date has no time zone; Kill Cord reads it as UTC. "Calls to this endpoint will
// not increase concurrency, but you can only call it 6 times per minute."
import Foundation

public struct ScrapingBeeProvider: SpendProvider {
    public let id = ProviderID.scrapingbee
    static let usageURL = URL(string: "https://app.scrapingbee.com/api/v1/usage")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the API key from your ScrapingBee dashboard.")
    }

    struct Usage: Decodable {
        let maxApiCredit: FlexibleDecimal
        let usedApiCredit: FlexibleDecimal
        let renewalSubscriptionDate: String?

        enum CodingKeys: String, CodingKey {
            case maxApiCredit = "max_api_credit"
            case usedApiCredit = "used_api_credit"
            case renewalSubscriptionDate = "renewal_subscription_date"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let usage = try await api.get(Usage.self, Self.usageURL, headers: ["Authorization": "Bearer \(key)"])
        let limit = usage.maxApiCredit.value
        let used = usage.usedApiCredit.value
        let balance = Balance(remaining: max(limit - used, 0), unit: .units("credits"), kind: .allowance,
                              limit: limit, used: used, resetsAt: usage.renewalSubscriptionDate.flatMap(Self.date))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    /// "2022-04-18T10:05:58.134716", with or without fractional seconds, read as UTC.
    static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let trimmed = String(text.prefix(19))
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: trimmed) ?? ISO8601.date(text)
    }
}
