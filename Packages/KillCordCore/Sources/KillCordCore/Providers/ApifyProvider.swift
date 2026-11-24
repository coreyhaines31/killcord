// Apify usage this cycle, and the usage limit.
// Reference: https://docs.apify.com/api/v2/users-me-limits-get
// The limit: https://docs.apify.com/platform/console/billing ("Apify platform services will be suspended").
//
// GET https://api.apify.com/v2/users/me/limits
//   headers: Authorization: Bearer <API token>
//   200:     { "data": { "monthlyUsageCycle": { "startAt": "2022-10-02T00:00:00.000Z", "endAt": "…" },
//                        "limits": { "maxMonthlyUsageUsd": 300, … }, "current": { "monthlyUsageUsd": 43, … } } }
// Both amounts are numbers in USD. Errors: { "error": { "type": "invalid-token", "message": "…" } }.
import Foundation

public struct ApifyProvider: SpendProvider {
    public let id = ProviderID.apify
    static let limitsURL = URL(string: "https://api.apify.com/v2/users/me/limits")!
    public static let usageLimitCapID = "apify.usage-limit"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a token that can read your account, or an "
            + "unscoped token.")
    }

    struct Limits: Decodable {
        let data: Details

        struct Details: Decodable {
            let monthlyUsageCycle: Cycle
            let limits: Caps
            let current: Current
        }

        struct Cycle: Decodable {
            let startAt: String
            let endAt: String
        }

        struct Caps: Decodable {
            let maxMonthlyUsageUsd: FlexibleDecimal
        }

        struct Current: Decodable {
            let monthlyUsageUsd: FlexibleDecimal
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    func read(_ credentials: ProviderCredentials) async throws -> Limits.Details {
        let key = try credentials.require("apiKey")
        return try await api.get(Limits.self, Self.limitsURL, headers: ["Authorization": "Bearer \(key)"]).data
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let details = try await read(credentials)
        guard let start = ISO8601.date(details.monthlyUsageCycle.startAt) else { throw SpendError.unexpectedResponse }
        let used = details.current.monthlyUsageUsd.value
        let limit = details.limits.maxMonthlyUsageUsd.value
        // What's left before Apify suspends the account's services this cycle.
        let left = Balance.usd(max(limit - used, 0), kind: .allowance, limit: limit,
                               resetsAt: ISO8601.date(details.monthlyUsageCycle.endAt))
        return SpendSnapshot(provider: id, today: nil, month: Money(used), monthKind: .billingPeriod(start: start),
                             balance: left, fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let details = try? await read(credentials) else { return [] }
        let used = details.current.monthlyUsageUsd.value
        let limit = details.limits.maxMonthlyUsageUsd.value
        let limitText = MoneyText.string(Money(limit))
        let status: CapVerification.Status = used >= limit
            ? .enforced("Apify reports \(MoneyText.string(Money(used))) used of a \(limitText) usage limit this "
                + "cycle, so its services are suspended until the cycle ends or you raise it.")
            : .on("Apify reports a usage limit of \(limitText) this cycle. Past it, Apify suspends its services.")
        return [CapVerification(capID: Self.usageLimitCapID, status: status, checkedAt: now)]
    }
}
