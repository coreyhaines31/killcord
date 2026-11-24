// DeepSeek account balance.
// Reference: https://api-docs.deepseek.com/api/get-user-balance
// Status codes: https://api-docs.deepseek.com/quick_start/error_codes (401, 402 Insufficient Balance, 429, 5xx)
//
// GET https://api.deepseek.com/user/balance
//   headers: Authorization: Bearer <API key>
//   200:     { "is_available": true,
//              "balance_infos": [ { "currency": "CNY" | "USD", "total_balance": "110.00",
//                                   "granted_balance": "10.00", "topped_up_balance": "100.00" } ] }
// Amounts are strings in major units, and an account can have one entry per currency. The docs list status
// codes but no error body.
import Foundation

public struct DeepSeekProvider: SpendProvider {
    public let id = ProviderID.deepseek
    static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from the account whose balance you want.")
    }

    struct UserBalance: Decodable {
        let balanceInfos: [Entry]

        struct Entry: Decodable {
            let currency: String
            let totalBalance: FlexibleDecimal

            enum CodingKeys: String, CodingKey {
                case currency
                case totalBalance = "total_balance"
            }
        }

        enum CodingKeys: String, CodingKey {
            case balanceInfos = "balance_infos"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let response = try await api.get(UserBalance.self, Self.balanceURL, headers: ["Authorization": "Bearer \(key)"])
        // One balance per currency. Kill Cord shows one: the USD balance when there is one.
        let entries = response.balanceInfos
        guard let entry = entries.first(where: { $0.currency.uppercased() == "USD" }) ?? entries.first else {
            throw SpendError.unexpectedResponse
        }
        let currency = Currency(entry.currency.uppercased())
        guard currency.code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw SpendError.unexpectedResponse
        }
        let balance = Balance(remaining: entry.totalBalance.value, unit: .money(currency))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
