// Bright Data account balance.
// Reference: https://docs.brightdata.com/api-reference/account-management-api/Get_total_balance_through_API
// Keys and permission levels: https://docs.brightdata.com/api-reference/authentication
//
// GET https://api.brightdata.com/customer/balance
//   headers: Authorization: Bearer <API key>
//   200:     { "balance": 220, "credit": 0, "prepayment": 0, "pending_costs": 0 }   (all numbers in USD)
// `balance` is "current available funds in your account". `pending_costs` are expected on next month's invoice:
// not what's left, so not shown. Free-tier credits aren't included. Bright Data's billing routes answer a
// missing permission with a plain-text 403, so there may be no message to show.
import Foundation

public struct BrightDataProvider: SpendProvider {
    public let id = ProviderID.brightdata
    static let balanceURL = URL(string: "https://api.brightdata.com/customer/balance")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a key with the Finance or Admin permission level.")
    }

    struct CustomerBalance: Decodable {
        let balance: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let account = try await api.get(CustomerBalance.self, Self.balanceURL, headers: ["Authorization": "Bearer \(key)"])
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: .usd(account.balance.value), fetchedAt: now)
    }
}
