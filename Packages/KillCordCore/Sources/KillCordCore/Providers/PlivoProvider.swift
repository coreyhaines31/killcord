// Plivo cash credits and auto recharge.
// Reference: https://www.plivo.com/docs/account/api/account/retrieve-account-details/
// Payments, auto recharge, monthly limits: https://www.plivo.com/docs/faq/billing-and-invoices/payments
//
// GET https://api.plivo.com/v1/Account/{auth_id}/
//   headers: Authorization: Basic base64(<Auth ID>:<Auth Token>)
//   200:     { "account_type": "standard", "auth_id": "MA…", "auto_recharge": false, "billing_mode": "prepaid",
//              "cash_credits": "1.80900", … }
// `cash_credits` is "Account credits in USD" (a string); `auto_recharge` is "Whether automatic recharge is enabled
// when credits fall below threshold"; `billing_mode` is "prepaid" or "postpaid".
import Foundation

public struct PlivoProvider: SpendProvider {
    public let id = ProviderID.plivo
    static let autoRechargeCapID = "plivo.auto-recharge-off"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the account's Auth ID and Auth Token.")
    }

    struct Account: Decodable {
        let cashCredits: FlexibleDecimal?
        let autoRecharge: Bool?
        let billingMode: String?

        var isPostpaid: Bool { billingMode?.lowercased() == "postpaid" }

        enum CodingKeys: String, CodingKey {
            case cashCredits = "cash_credits"
            case autoRecharge = "auto_recharge"
            case billingMode = "billing_mode"
        }
    }

    static func accountURL(authID: String) throws -> URL {
        // An Auth ID is letters and digits; anything else would change the path.
        guard authID.range(of: "\\A[A-Za-z0-9]+\\z", options: .regularExpression) != nil,
              let url = URL(string: "https://api.plivo.com/v1/Account/\(authID)/") else {
            throw SpendError.invalidKey
        }
        return url
    }

    func read(_ credentials: ProviderCredentials) async throws -> Account {
        let authID = try credentials.require("authID").trimmingCharacters(in: .whitespacesAndNewlines)
        let token = try credentials.require("authToken")
        let basic = Data("\(authID):\(token)".utf8).base64EncodedString()
        return try await api.get(Account.self, try Self.accountURL(authID: authID),
                                 headers: ["Authorization": "Basic \(basic)"])
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let account = try await read(credentials)
        if account.isPostpaid {
            throw SpendError.planNotSupported("Plivo bills this account after use, so its credits don't limit "
                + "spending. Kill Cord shows prepaid Plivo accounts only.")
        }
        guard let credits = account.cashCredits?.value else { throw SpendError.unexpectedResponse }
        let balance = Balance.usd(credits)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let account = try? await read(credentials), let autoRecharge = account.autoRecharge else { return [] }
        // A postpaid account is invoiced, so running out of credits stops nothing.
        if account.isPostpaid {
            return [CapVerification(capID: Self.autoRechargeCapID, status: .off("Plivo invoices this account after "
                + "use, so its credits don't stop spending."), checkedAt: now)]
        }
        let status: CapVerification.Status = autoRecharge
            ? .off("Plivo reports auto recharge is on, so credits are topped up instead of running out.")
            : .on("Plivo reports auto recharge is off, so nothing tops up the credits.")
        return [CapVerification(capID: Self.autoRechargeCapID, status: status, checkedAt: now)]
    }
}
