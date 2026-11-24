// Telnyx account balance and auto recharge.
// Balance: https://developers.telnyx.com/api-reference/billing/get-user-balance-details
// Auto recharge: https://developers.telnyx.com/api-reference/autorechargepreferences/list-auto-recharge-preferences
// Keys: https://developers.telnyx.com/docs/development/api-fundamentals/authentication (no scopes documented)
//
// GET https://api.telnyx.com/v2/balance
//   headers: Authorization: Bearer <API key>
//   200:     { "data": { "record_type": "balance", "pending": "10.00", "balance": "300.00",
//                        "credit_limit": "100.00", "available_credit": "400.00", "currency": "USD" } }
// `available_credit` is the "Available amount to spend (balance + credit limit)". Amounts are strings.
// GET https://api.telnyx.com/v2/payment/auto_recharge_prefs
//   200:     { "data": { "enabled": true, "threshold_amount": "104.00", "recharge_amount": "104.00", … } }
// Errors: { "errors": [ { "code": "10010", "title": "Authorization failed", "detail": "…" } ] }.
import Foundation

public struct TelnyxProvider: SpendProvider {
    public let id = ProviderID.telnyx
    static let balanceURL = URL(string: "https://api.telnyx.com/v2/balance")!
    static let autoRechargeURL = URL(string: "https://api.telnyx.com/v2/payment/auto_recharge_prefs")!
    static let autoRechargeCapID = "telnyx.auto-recharge-off"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from the account whose balance you want.")
    }

    struct BalanceReply: Decodable {
        let data: Details

        struct Details: Decodable {
            let availableCredit: FlexibleDecimal
            let currency: String

            enum CodingKeys: String, CodingKey {
                case availableCredit = "available_credit"
                case currency
            }
        }
    }

    struct AutoRechargeReply: Decodable {
        let data: Preference

        struct Preference: Decodable {
            let enabled: Bool
            let thresholdAmount: FlexibleDecimal?
            let rechargeAmount: FlexibleDecimal?

            enum CodingKeys: String, CodingKey {
                case enabled
                case thresholdAmount = "threshold_amount"
                case rechargeAmount = "recharge_amount"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(BalanceReply.self, Self.balanceURL, headers: ["Authorization": "Bearer \(key)"])
        let currency = Currency(reply.data.currency.uppercased())
        guard currency.code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw SpendError.unexpectedResponse
        }
        let balance = Balance(remaining: reply.data.availableCredit.value, unit: .money(currency))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let key = try? credentials.require("apiKey"),
              let reply = try? await api.get(AutoRechargeReply.self, Self.autoRechargeURL,
                                             headers: ["Authorization": "Bearer \(key)"]) else { return [] }
        let preference = reply.data
        let status: CapVerification.Status
        if preference.enabled {
            var detail = "Telnyx reports auto recharge is on"
            if let threshold = preference.thresholdAmount?.value, let amount = preference.rechargeAmount?.value {
                detail += ": below \(BalanceText.number(threshold)) it recharges \(BalanceText.number(amount)) more"
            }
            status = .off(detail + ", so the balance doesn't stop spending.")
        } else {
            status = .on("Telnyx reports auto recharge is off, so nothing tops up the balance.")
        }
        return [CapVerification(capID: Self.autoRechargeCapID, status: status, checkedAt: now)]
    }
}
