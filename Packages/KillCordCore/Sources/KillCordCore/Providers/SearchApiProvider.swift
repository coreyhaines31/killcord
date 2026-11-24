// SearchApi searches left and automatic early renewal.
// Reference: https://www.searchapi.io/docs/account-api
//
// GET https://www.searchapi.io/api/v1/me
//   headers: Authorization: Bearer <API key>   (also accepted as ?api_key=; Kill Cord uses the header)
//   200:     { "account": { "current_month_usage": 4800, "monthly_allowance": 10000, "remaining_credits": 0,
//                           "remaining_searches": 5200, "has_automatic_early_renewal_enabled": true },
//              "api_usage": { … }, "subscription": { "period_start": "…Z", "period_end": "2025-01-04T00:34:59Z" } }
// `remaining_searches` is "the unused monthly allowance plus remaining_credits". "At 0, searches are rejected until
// the allowance renews or credits are added." `has_automatic_early_renewal_enabled` is true when on, else absent.
import Foundation

public struct SearchApiProvider: SpendProvider {
    public let id = ProviderID.searchapi
    static let meURL = URL(string: "https://www.searchapi.io/api/v1/me")!
    static let earlyRenewalCapID = "searchapi.early-renewal-off"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the API key from your SearchApi dashboard.")
    }

    struct Profile: Decodable {
        let account: Account
        let subscription: Subscription?

        struct Account: Decodable {
            let currentMonthUsage: FlexibleDecimal?
            let monthlyAllowance: FlexibleDecimal?
            let remainingSearches: FlexibleDecimal
            let hasAutomaticEarlyRenewalEnabled: Bool?

            enum CodingKeys: String, CodingKey {
                case currentMonthUsage = "current_month_usage"
                case monthlyAllowance = "monthly_allowance"
                case remainingSearches = "remaining_searches"
                case hasAutomaticEarlyRenewalEnabled = "has_automatic_early_renewal_enabled"
            }
        }

        struct Subscription: Decodable {
            let periodEnd: String?

            enum CodingKeys: String, CodingKey {
                case periodEnd = "period_end"
            }
        }
    }

    func read(_ credentials: ProviderCredentials) async throws -> Profile {
        let key = try credentials.require("apiKey")
        return try await api.get(Profile.self, Self.meURL, headers: ["Authorization": "Bearer \(key)"])
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let profile = try await read(credentials)
        let account = profile.account
        let balance = Balance(remaining: account.remainingSearches.value, unit: .units("searches"), kind: .allowance,
                              limit: account.monthlyAllowance?.value, used: account.currentMonthUsage?.value,
                              resetsAt: profile.subscription?.periodEnd.flatMap(ISO8601.date))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let profile = try? await read(credentials) else { return [] }
        let status: CapVerification.Status = profile.account.hasAutomaticEarlyRenewalEnabled == true
            ? .off("SearchApi reports automatic early renewal is on, so running out starts a new paid period.")
            : .on("SearchApi reports automatic early renewal is off, so searches stop at zero until the allowance "
                + "renews.")
        return [CapVerification(capID: Self.earlyRenewalCapID, status: status, checkedAt: now)]
    }
}
