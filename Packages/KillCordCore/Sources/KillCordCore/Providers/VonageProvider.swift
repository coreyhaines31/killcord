// Vonage account balance (EUR) and auto reload.
// Reference: https://developer.vonage.com/en/api/account ("Get Account Balance")
// Payments and auto reload: https://developer.vonage.com/en/account/guides/payments
//
// GET https://rest.nexmo.com/account/get-balance
//   headers: Authorization: Basic base64(<API key>:<API secret>)
//   200:     { "value": 10.28, "autoReload": false }
// `value` is "The balance of the account, in EUR"; `autoReload` is "Whether the account has auto-reloading
// enabled." The page documents no error body for this call.
import Foundation

public struct VonageProvider: SpendProvider {
    public let id = ProviderID.vonage
    static let balanceURL = URL(string: "https://rest.nexmo.com/account/get-balance")!
    static let autoReloadCapID = "vonage.auto-reload-off"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the account's API key and one of its API secrets.")
    }

    struct AccountBalance: Decodable {
        let value: FlexibleDecimal
        let autoReload: Bool?
    }

    func read(_ credentials: ProviderCredentials) async throws -> AccountBalance {
        let key = try credentials.require("apiKey")
        let secret = try credentials.require("apiSecret")
        let basic = Data("\(key):\(secret)".utf8).base64EncodedString()
        return try await api.get(AccountBalance.self, Self.balanceURL, headers: ["Authorization": "Basic \(basic)"])
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let reply = try await read(credentials)
        let balance = Balance(remaining: reply.value.value, unit: .money(Currency("EUR")))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let reply = try? await read(credentials), let autoReload = reply.autoReload else { return [] }
        let status: CapVerification.Status = autoReload
            ? .off("Vonage reports auto reload is on, so the balance is topped up instead of running out.")
            : .on("Vonage reports auto reload is off, so spending stops when the balance reaches zero.")
        return [CapVerification(capID: Self.autoReloadCapID, status: status, checkedAt: now)]
    }
}
