// Kimi (Moonshot AI) balance, for accounts on platform.kimi.ai (the global platform; amounts in USD).
//
// With an Admin key (recommended): https://platform.kimi.ai/docs/admin-api/billing-account
// GET https://api.moonshot.ai/v1/admin/organizations/account
//   headers: Authorization: Bearer sk-admin-…   (needs the billing:read scope; Admin keys can't call inference)
//   200:     { "available_balance": 4958894, "total_consume": …, "total_recharge_amount": …, "total_voucher_amount": … }
// Amounts are integers in milli-cent: "1 USD = 100,000 milli-cent".
// Errors: { "error": { "type": "…", "code": "insufficient_scope", "message": "…", "param": null, "request_id": "…" } }.
//
// With an inference API key: https://platform.kimi.ai/docs/api/balance
// GET https://api.moonshot.ai/v1/users/me/balance
//   headers: Authorization: Bearer <API key>
//   200:     { "code": 0, "data": { "available_balance": 49.58894, "voucher_balance": 46.58893,
//              "cash_balance": 3.00001 }, "scode": "0x0", "status": true }
// Amounts are numbers in USD ("unit: USD"). `code` 0 means success.
import Foundation

public struct KimiProvider: SpendProvider {
    public let id = ProviderID.moonshot
    static let adminAccountURL = URL(string: "https://api.moonshot.ai/v1/admin/organizations/account")!
    static let balanceURL = URL(string: "https://api.moonshot.ai/v1/users/me/balance")!
    static let milliCentsPerDollar = Decimal(100_000)

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Give the Admin key the billing:read scope.")
    }

    struct OrgAccount: Decodable {
        let availableBalance: FlexibleDecimal

        enum CodingKeys: String, CodingKey {
            case availableBalance = "available_balance"
        }
    }

    struct UserBalance: Decodable {
        let code: Int
        let data: Amounts

        struct Amounts: Decodable {
            let availableBalance: FlexibleDecimal

            enum CodingKeys: String, CodingKey {
                case availableBalance = "available_balance"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let headers = ["Authorization": "Bearer \(key)"]
        let dollars: Decimal
        if key.hasPrefix("sk-admin-") {
            let account = try await api.get(OrgAccount.self, Self.adminAccountURL, headers: headers)
            dollars = account.availableBalance.value / Self.milliCentsPerDollar
        } else {
            let balance = try await api.get(UserBalance.self, Self.balanceURL, headers: headers)
            guard balance.code == 0 else { throw SpendError.unexpectedResponse }
            dollars = balance.data.availableBalance.value
        }
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: .usd(dollars), fetchedAt: now)
    }
}
