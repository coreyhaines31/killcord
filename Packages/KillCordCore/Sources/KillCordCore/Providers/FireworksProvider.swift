// Fireworks AI spend today and this month, and the monthly spend limit.
// Billing summary: https://docs.fireworks.ai/api-reference/get-billing-summary (server https://api.fireworks.ai)
// Accounts: https://docs.fireworks.ai/api-reference/list-accounts. Quotas: https://docs.fireworks.ai/api-reference/get-quota
// Spend limit: https://docs.fireworks.ai/guides/quotas_usage/account-quotas (quota `monthly-spend-usd`).
// Guide: https://docs.fireworks.ai/accounts/exporting-usage-and-costs ("Any key on the target account works").
//
// GET https://api.fireworks.ai/v1/accounts   (only when no account ID is saved, and only if the key sees one)
//   200: { "accounts": [{ "name": "accounts/my-account", … }], "nextPageToken": "…" }
// GET https://api.fireworks.ai/v1/accounts/{account_id}/billing/summary?startTime=…&endTime=…
//   headers: Authorization: Bearer <API key>
//   200: { "lineItems": [{ "category": "…", "totalCost": { "currencyCode": "USD", "units": "12", "nanos": 340000000 },
//                          … }] }
// `startTime` and `endTime` are required; only their date counts, and `endTime` is exclusive. Amounts are rated before
// credits are applied. The docs give no example, only the schema.
// GET https://api.fireworks.ai/v1/accounts/{account_id}/quotas/monthly-spend-usd
//   200: { "name": "accounts/my-account/quotas/monthly-spend-usd", "value": "200", "maxValue": "…", "usage": 41.5 }
import Foundation

public struct FireworksProvider: SpendProvider {
    public let id = ProviderID.fireworks
    public static let spendLimitCapID = "fireworks.monthly-spend-limit"
    static let base = URL(string: "https://api.fireworks.ai/v1/accounts")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key on the Fireworks account you want to "
            + "watch.")
    }

    struct Accounts: Decodable {
        let accounts: [Account]

        struct Account: Decodable {
            let name: String
        }
    }

    struct Summary: Decodable {
        let lineItems: [LineItem]?

        struct LineItem: Decodable {
            let totalCost: Amount?
        }
    }

    struct Amount: Decodable {
        let currencyCode: String?
        let units: FlexibleDecimal?
        let nanos: FlexibleDecimal?

        var value: Decimal { (units?.value ?? 0) + (nanos?.value ?? 0) / 1_000_000_000 }
    }

    struct Quota: Decodable {
        let value: FlexibleDecimal
        let usage: FlexibleDecimal?
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    func account(_ credentials: ProviderCredentials, headers: [String: String]) async throws -> String {
        if let saved = credentials["accountID"] {
            // It goes into the path, so only the characters an ID can have.
            guard FieldFormat.isIdentifier(saved) else {
                throw SpendError.requiresSetup("the account ID doesn't look right. Copy it from the Fireworks "
                    + "dashboard.")
            }
            return saved
        }
        let accounts = try await api.get(Accounts.self, Self.base, headers: headers).accounts
        let ids = accounts.compactMap { $0.name.split(separator: "/").last.map(String.init) }
        guard ids.count == 1, let only = ids.first, FieldFormat.isIdentifier(only) else {
            throw SpendError.requiresSetup(ids.isEmpty
                ? "this key can't see a Fireworks account."
                : "this key can see \(ids.count) accounts. Add the account ID to choose one.")
        }
        return only
    }

    func total(_ account: String, from start: Date, to end: Date, headers: [String: String]) async throws -> Money {
        let url = Self.base.appendingPathComponent(account).appendingPathComponent("billing/summary").adding([
            URLQueryItem(name: "startTime", value: ISO8601.string(start)),
            URLQueryItem(name: "endTime", value: ISO8601.string(end))
        ])
        let items = try await api.get(Summary.self, url, headers: headers).lineItems ?? []
        let currencies = Set(items.compactMap { $0.totalCost?.currencyCode?.uppercased() })
        guard currencies.isSubset(of: ["USD", ""]) else { throw SpendError.unexpectedResponse }
        return Money(items.reduce(Decimal(0)) { $0 + ($1.totalCost?.value ?? 0) })
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let headers = ["Authorization": "Bearer \(key)"]
        let account = try await account(credentials, headers: headers)
        let window = window(now)
        let month = try await total(account, from: window.monthStart, to: window.dayEnd, headers: headers)
        let today = try await total(account, from: window.dayStart, to: window.dayEnd, headers: headers)
        return SpendSnapshot(provider: id, today: today, month: month, fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let key = try? credentials.require("apiKey") else { return [] }
        let headers = ["Authorization": "Bearer \(key)"]
        guard let account = try? await account(credentials, headers: headers) else { return [] }
        let url = Self.base.appendingPathComponent(account).appendingPathComponent("quotas/monthly-spend-usd")
        guard let quota = try? await api.get(Quota.self, url, headers: headers) else { return [] }
        let limit = quota.value.value
        guard limit > 0 else {
            return [CapVerification(capID: Self.spendLimitCapID,
                                    status: .off("Fireworks reports no monthly spend limit."), checkedAt: now)]
        }
        let limitText = MoneyText.string(Money(limit))
        let used = quota.usage?.value ?? 0
        let status: CapVerification.Status = used >= limit
            ? .enforced("Fireworks reports \(MoneyText.string(Money(used))) used of a \(limitText) monthly spend "
                + "limit, so API requests are paused until you raise it.")
            : .on("Fireworks reports a monthly spend limit of \(limitText). At it, API requests pause.")
        return [CapVerification(capID: Self.spendLimitCapID, status: status, checkedAt: now)]
    }
}
