// Mistral spend this month and the Organization spending limit, from the Admin API (beta, Enterprise plans only).
// Reference: https://docs.mistral.ai/api/endpoint/beta/admin/billing ("Get Spend Limits")
// Guide: https://docs.mistral.ai/admin/admin-api/usage-metrics
// Limits: https://docs.mistral.ai/admin/billing-usage/usage-limits
//
// GET https://api.mistral.ai/v1/admin/spend-limit
//   headers: x-api-key: <Admin API key>   (https://docs.mistral.ai/admin/admin-api/authentication; the generated
//            reference's example shows a Bearer header, but the authentication page names x-api-key)
//   200:     { "limits": { "completion": { "monthly_limit_reached": false, "no_monthly_limit": false,
//                                          "total_usage": 41.5, "usage": …, "usage_limit": 500, "vibe_usage": … },
//                          "currency": "USD", "last_payment_failure": false, … } }
// `total_usage` is "Total current usage counted against the limit", in `currency`; `usage_limit` is the monthly limit.
// The documented example shows only `monthly_limit_reached`; the other fields are in its schema.
import Foundation

public struct MistralProvider: SpendProvider {
    public let id = ProviderID.mistral
    public static let spendLimitCapID = "mistral.org-spend-limit"
    static let spendLimitURL = URL(string: "https://api.mistral.ai/v1/admin/spend-limit")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an Admin API key. Standard API keys don't work with "
            + "admin endpoints, and the Admin API is Enterprise-only.")
    }

    struct Response: Decodable {
        let limits: Limits

        struct Limits: Decodable {
            let completion: Completion?
            let currency: String?
        }

        struct Completion: Decodable {
            let monthlyLimitReached: Bool?
            let noMonthlyLimit: Bool?
            let totalUsage: FlexibleDecimal?
            let usageLimit: FlexibleDecimal?

            enum CodingKeys: String, CodingKey {
                case monthlyLimitReached = "monthly_limit_reached"
                case noMonthlyLimit = "no_monthly_limit"
                case totalUsage = "total_usage"
                case usageLimit = "usage_limit"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    func read(_ credentials: ProviderCredentials) async throws -> (Response.Completion, Currency) {
        let key = try credentials.require("apiKey")
        let response = try await api.get(Response.self, Self.spendLimitURL,
                                         headers: ["x-api-key": key])
        let code = (response.limits.currency ?? "USD").uppercased()
        guard let completion = response.limits.completion,
              code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw SpendError.unexpectedResponse
        }
        return (completion, Currency(code))
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let (completion, currency) = try await read(credentials)
        guard let used = completion.totalUsage?.value else { throw SpendError.unexpectedResponse }
        return SpendSnapshot(provider: id, today: nil, month: Money(used, currency), fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let (completion, currency) = try? await read(credentials) else { return [] }
        let status: CapVerification.Status
        if completion.monthlyLimitReached == true {
            status = .enforced("Mistral reports the monthly spending limit is reached, so API access can be "
                + "suspended until next month or until an admin raises it.")
        } else if completion.noMonthlyLimit == true {
            status = .off("Mistral reports no monthly spending limit for the Organization.")
        } else if let limit = completion.usageLimit?.value {
            status = .on("Mistral reports a monthly spending limit of \(MoneyText.string(Money(limit, currency))).")
        } else {
            return []
        }
        return [CapVerification(capID: Self.spendLimitCapID, status: status, checkedAt: now)]
    }
}
