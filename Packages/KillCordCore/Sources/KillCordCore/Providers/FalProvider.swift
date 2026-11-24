// fal credit balance.
// Reference: https://fal.ai/docs/platform-apis/v1/account/billing
// Keys: https://fal.ai/docs/documentation/model-apis/authentication/key-based (presets BILLING, READONLY, FULL).
//
// GET https://api.fal.ai/v1/account/billing?expand=credits
//   headers: Authorization: Key <key>   (needs billing:usage:read: the BILLING, READONLY and FULL presets have it)
//   200:     { "username": "my-team", "credits": { "current_balance": 24.5, "currency": "USD" } }
// `credits` is there only with expand=credits. `current_balance` is a number in major units (dollars).
// Errors: { "error": { "type": "authorization_error", "message": "Authentication required" } }.
import Foundation

public struct FalProvider: SpendProvider {
    public let id = ProviderID.fal
    static let billingURL = URL(string: "https://api.fal.ai/v1/account/billing?expand=credits")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Create a key with the BILLING preset, which has "
            + "the billing:usage:read permission.")
    }

    struct Billing: Decodable {
        let credits: Credits

        struct Credits: Decodable {
            let currentBalance: FlexibleDecimal
            let currency: String

            enum CodingKeys: String, CodingKey {
                case currentBalance = "current_balance"
                case currency
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let billing = try await api.get(Billing.self, Self.billingURL, headers: ["Authorization": "Key \(key)"])
        let currency = Currency(billing.credits.currency.uppercased())
        guard currency.code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            throw SpendError.unexpectedResponse
        }
        let balance = Balance(remaining: billing.credits.currentBalance.value, unit: .money(currency))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
