// LlamaCloud (LlamaParse) organization usage: this billing period's invoice so far, and the plan's spending limit.
// Usage: https://admin.api.llamaindex.ai/api/resources/organizations/methods/get_usage
// Organizations: https://admin.api.llamaindex.ai/api/resources/organizations/methods/list
// Keys and regions: https://admin.api.llamaindex.ai/ ("An API key inherits its owner's privileges"; a key from the
// User API Keys table is needed, since a project key "cannot reach the organization surface at all").
// Billing: https://developers.llamaindex.ai/llamaparse/general/billing/
//
// GET https://api.cloud.llamaindex.ai/api/v2/organizations   (EU: api.cloud.eu.llamaindex.ai)
//   headers: Authorization: Bearer <user API key>
//   200:     { "items": [{ "id": "…", "name": "…" }], "next_page_token": … }
// Used only when no organization ID is saved, and only when the key sees exactly one organization.
//
// GET https://api.cloud.llamaindex.ai/api/v1/organizations/{organization_id}/usage?get_current_invoice_total=true
//   200: { "plan": { "limits": { "max_monthly_invoice_total_usd": 0, … },
//                    "current_billing_period": { "start_date": "…", "end_date": "…" }, … },
//          "usage": { "active_alerts": ["plan_spend_limit_exceeded", …], "current_invoice_total_usd_cents": 1234,
//                     "active_free_credits_usage": [{ "remaining_balance": 0, … }], … } }
// The invoice total is in cents; the limit is in dollars. Errors carry `detail`; 404 "Organization <id> not found" is
// the ordinary authorization failure.
import Foundation

public struct LlamaCloudProvider: SpendProvider {
    public let id = ProviderID.llamacloud
    public static let spendLimitCapID = "llamacloud.spend-limit"
    static let hosts = ["US": "api.cloud.llamaindex.ai", "EU": "api.cloud.eu.llamaindex.ai"]
    static let limitAlerts: Set<String> = ["plan_spend_limit_exceeded", "configured_spend_limit_exceeded"]

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a key from the User API Keys table. Project keys "
            + "can't read organization usage.")
    }

    struct Organizations: Decodable {
        let items: [Organization]

        struct Organization: Decodable {
            let id: String
        }
    }

    struct UsageAndPlan: Decodable {
        let plan: Plan
        let usage: Usage

        struct Plan: Decodable {
            let limits: Limits?
            let currentBillingPeriod: Period?

            enum CodingKeys: String, CodingKey {
                case limits
                case currentBillingPeriod = "current_billing_period"
            }
        }

        struct Limits: Decodable {
            let maxMonthlyInvoiceTotalUsd: FlexibleDecimal?

            enum CodingKeys: String, CodingKey {
                case maxMonthlyInvoiceTotalUsd = "max_monthly_invoice_total_usd"
            }
        }

        struct Period: Decodable {
            let startDate: String

            enum CodingKeys: String, CodingKey {
                case startDate = "start_date"
            }
        }

        struct Usage: Decodable {
            let activeAlerts: [String]?
            let currentInvoiceTotalUsdCents: FlexibleDecimal?

            enum CodingKeys: String, CodingKey {
                case activeAlerts = "active_alerts"
                case currentInvoiceTotalUsdCents = "current_invoice_total_usd_cents"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    func read(_ credentials: ProviderCredentials) async throws -> UsageAndPlan {
        let key = try credentials.require("apiKey")
        let host = Self.hosts[credentials["region"] ?? "US"] ?? Self.hosts["US"]!
        let headers = ["Authorization": "Bearer \(key)"]
        let organization: String
        if let saved = credentials["organizationID"] {
            // It goes into the path, so only the characters an ID can have.
            guard FieldFormat.isIdentifier(saved) else {
                throw SpendError.requiresSetup("the organization ID doesn't look right. Copy it from Organization "
                    + "Settings.")
            }
            organization = saved
        } else {
            let list = try await api.get(Organizations.self, URL(string: "https://\(host)/api/v2/organizations")!,
                                         headers: headers)
            guard list.items.count == 1, let only = list.items.first, FieldFormat.isIdentifier(only.id) else {
                throw SpendError.requiresSetup(list.items.isEmpty
                    ? "this key can't see an organization. Use a key from the User API Keys table."
                    : "this key can see \(list.items.count) organizations. Add the organization ID to choose one.")
            }
            organization = only.id
        }
        let url = URL(string: "https://\(host)/api/v1/organizations/\(organization)/usage")!
            .adding([URLQueryItem(name: "get_current_invoice_total", value: "true")])
        return try await api.get(UsageAndPlan.self, url, headers: headers)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let usage = try await read(credentials)
        guard let cents = usage.usage.currentInvoiceTotalUsdCents?.value else { throw SpendError.unexpectedResponse }
        let monthKind: SpendSnapshot.MonthKind = usage.plan.currentBillingPeriod
            .flatMap { ISO8601.date($0.startDate) }.map { .billingPeriod(start: $0) } ?? .calendarMonth
        return SpendSnapshot(provider: id, today: nil, month: Money(cents / 100), monthKind: monthKind,
                             fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let usage = try? await read(credentials) else { return [] }
        let alerts = Set(usage.usage.activeAlerts ?? [])
        let limit = usage.plan.limits?.maxMonthlyInvoiceTotalUsd?.value ?? 0
        let status: CapVerification.Status
        if !alerts.isDisjoint(with: Self.limitAlerts) {
            status = .enforced("LlamaCloud reports the spending limit is exceeded, so new jobs are refused until "
                + "the next billing period.")
        } else if limit > 0 {
            status = .on("LlamaCloud reports a monthly invoice limit of \(MoneyText.string(Money(limit))).")
        } else {
            status = .off("LlamaCloud reports no monthly invoice limit on this plan.")
        }
        return [CapVerification(capID: Self.spendLimitCapID, status: status, checkedAt: now)]
    }
}
