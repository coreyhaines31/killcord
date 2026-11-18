// Monid wallet balance.
// Public docs: https://monid.ai/SKILL.md (keys from https://app.monid.ai/access/api-keys, `monid_<stage>_<secret>`).
// The route comes from the official CLI, @monid-ai/cli 0.1.9 on npm (`getBalance`, `formatBalance`). There's no
// docs page for it, so a change on Monid's side shows as "unexpected response".
//
// GET https://api.monid.ai/v1/wallet/balance
//   headers: Authorization: Bearer <API key>
//   200:     { "balance": { "value": 12.5, "currency": "USD" }, "hints": … }
// Errors: { "error": { "code": "…", "message": "…" } }.
import Foundation

public struct MonidProvider: SpendProvider {
    public let id = ProviderID.monid
    static let balanceURL = URL(string: "https://api.monid.ai/v1/wallet/balance")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Create a key that can read the wallet on Monid's API keys page.")
    }

    struct Wallet: Decodable {
        let balance: Amount

        struct Amount: Decodable {
            let value: FlexibleDecimal
            let currency: String
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let wallet = try await api.get(Wallet.self, Self.balanceURL, headers: ["Authorization": "Bearer \(key)"])
        let currency = Currency(wallet.balance.currency)
        guard currency.code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw SpendError.unexpectedResponse
        }
        let balance = Balance(remaining: wallet.balance.value.value, unit: .money(currency))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
