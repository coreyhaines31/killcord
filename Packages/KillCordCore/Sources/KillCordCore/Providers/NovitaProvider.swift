// Novita AI account balance.
// Reference: https://docs.novita.ai/api-reference/basic-get-user-balance
// Auth: https://docs.novita.ai/api-reference/basic-authentication
// Errors: https://docs.novita.ai/api-reference/basic-error-code
//
// GET https://api.novita.ai/openapi/v1/billing/balance/detail
//   headers: Authorization: Bearer <API key>
//   200:     { "availableBalance": "1000000", "cashBalance": "800000", "creditLimit": "200000",
//              "pendingCharges": "0", "outstandingInvoices": "0" }
// Every amount is a string in "1/10000 USD (e.g., 10000 = $1.00)". `availableBalance` is "The user's credit
// balance"; in the documented example it's the cash balance plus the credit limit.
import Foundation

public struct NovitaProvider: SpendProvider {
    public let id = ProviderID.novita
    static let balanceURL = URL(string: "https://api.novita.ai/openapi/v1/billing/balance/detail")!
    /// Novita's amounts are in 1/10000 USD.
    static let unitsPerDollar: Decimal = 10000

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from the account whose balance you want.")
    }

    struct BalanceDetail: Decodable {
        let availableBalance: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(BalanceDetail.self, Self.balanceURL, headers: ["Authorization": "Bearer \(key)"])
        let balance = Balance.usd(reply.availableBalance.value / Self.unitsPerDollar)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
