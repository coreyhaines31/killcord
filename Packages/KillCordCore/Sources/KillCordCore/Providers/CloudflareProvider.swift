// Cloudflare API, Billable Usage (FOCUS) and Spend Management policies.
// Billable usage: https://developers.cloudflare.com/api/resources/billing/subresources/usage/methods/get_account_usage_v1/
// Announcement: https://blog.cloudflare.com/billable-usage-api/
// Spend Management: https://developers.cloudflare.com/billing/manage/spend-management/
// Spend policies: https://developers.cloudflare.com/api/resources/billing/subresources/spend_policies/methods/list
// Permissions: https://developers.cloudflare.com/billing/understand/billing-permissions/
//
// GET https://api.cloudflare.com/client/v4/accounts/{account_id}/billable-usage
//   headers: Authorization: Bearer <API token with Billing Read>
//   query:   from, to (optional). With neither, the current billing period, which follows the billing cycle,
//            not the calendar month. A range that misses the cycle's anchor day returns nothing, so Kill Cord
//            asks for the current period and filters days itself.
//   200:     { result: [{ BilledCost: 0.75, BillingCurrency: "USD", BillingPeriodStart, ChargePeriodStart,
//              ChargePeriodEnd, ServiceName, … }], success: true, errors: [], messages: [] }
// Amounts are numbers in dollars. Data updates daily, so today is usually not reported yet. The API is
// marked Alpha, and covers pay-as-you-go (self-serve) usage only, not Enterprise contracts or plan fees.
//
// GET https://api.cloudflare.com/client/v4/accounts/{account_id}/billing/spend-policies
//   200: { result: [{ action: "usage_block" | "notification", product_id: "workers" | "durable_objects",
//          threshold_cents, enabled, current_state: { status: "below_limit" | "limit_reached" | … } }] }
import Foundation

public struct CloudflareProvider: SpendProvider {
    public let id = ProviderID.cloudflare
    static let base = URL(string: "https://api.cloudflare.com/client/v4/accounts/")!
    public static let spendLimitCapID = "cloudflare.spend-limit"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Edit the API token and add the Billing Read "
            + "permission for this account.")
    }

    struct Envelope<Result: Decodable>: Decodable {
        let result: Result?
        let success: Bool
    }

    struct Usage: Decodable {
        let billedCost: FlexibleDecimal
        let billingCurrency: String?
        let billingPeriodStart: String?
        let chargePeriodStart: String

        enum CodingKeys: String, CodingKey {
            case billedCost = "BilledCost"
            case billingCurrency = "BillingCurrency"
            case billingPeriodStart = "BillingPeriodStart"
            case chargePeriodStart = "ChargePeriodStart"
        }
    }

    struct SpendPolicy: Decodable {
        struct State: Decodable {
            let status: String?
        }

        let action: String
        let productID: String?
        let thresholdCents: Int?
        let enabled: Bool?
        let currentState: State?

        enum CodingKeys: String, CodingKey {
            case action
            case productID = "product_id"
            case thresholdCents = "threshold_cents"
            case enabled
            case currentState = "current_state"
        }
    }

    func accountURL(_ accountID: String, _ path: String) throws -> URL {
        guard FieldFormat.isIdentifier(accountID) else { throw SpendError.notConfigured }
        return Self.base.appendingPathComponent(accountID).appendingPathComponent(path)
    }

    func headers(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "accept": "application/json"]
    }

    func usage(_ credentials: ProviderCredentials) async throws -> [Usage] {
        let token = try credentials.require("token")
        let url = try accountURL(try credentials.require("accountID"), "billable-usage")
        let envelope = try await api.get(Envelope<[Usage]>.self, url, headers: headers(token))
        guard envelope.success, let result = envelope.result else { throw SpendError.unexpectedResponse }
        return result
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await usage(credentials)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let rows = try await usage(credentials)
        let periodStart = rows.compactMap { $0.billingPeriodStart.flatMap(ISO8601.date) }.min()
        return try FOCUSTotals.snapshot(
            provider: id, rows: rows.map { ($0.billedCost.value, $0.billingCurrency, $0.chargePeriodStart) },
            window: window(now), monthKind: periodStart.map { .billingPeriod(start: $0) } ?? .calendarMonth, now: now
        )
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let token = credentials["token"], let accountID = credentials["accountID"],
              let url = try? accountURL(accountID, "billing/spend-policies"),
              let envelope = try? await api.get(Envelope<[SpendPolicy]>.self, url, headers: headers(token)),
              envelope.success, let policies = envelope.result
        else { return [] }
        let blocking = policies.filter { $0.action == "usage_block" && $0.enabled != false }
        let status: CapVerification.Status
        if let reached = blocking.first(where: { $0.currentState?.status == "limit_reached" }) {
            status = .enforced("Cloudflare reports the \(Self.product(reached)) spend limit was reached; usage is "
                + "blocked until the next billing period or until you raise it.")
        } else if !blocking.isEmpty {
            let list = blocking.map { "\(Self.product($0)) at \(MoneyText.string(.fromCents($0.thresholdCents ?? 0)))" }
            status = .on("Cloudflare reports a spend limit that blocks usage: \(list.joined(separator: ", ")).")
        } else if policies.contains(where: { $0.action == "notification" && $0.enabled != false }) {
            status = .off("Cloudflare has spend alerts set, but no limit that blocks usage.")
        } else {
            status = .off("Cloudflare reports no spend limit.")
        }
        return [CapVerification(capID: Self.spendLimitCapID, status: status, checkedAt: now)]
    }

    static func product(_ policy: SpendPolicy) -> String {
        switch policy.productID {
        case "workers": "Workers"
        case "durable_objects": "Durable Objects"
        default: policy.productID ?? "product"
        }
    }
}

/// Checks for values that end up in a URL path, so a pasted value can't change which endpoint is called.
enum FieldFormat {
    static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128
            && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
            && value.unicodeScalars.allSatisfy(\.isASCII)
    }
}
