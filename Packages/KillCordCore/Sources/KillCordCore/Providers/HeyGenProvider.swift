// HeyGen balance, spending cap and auto reload.
// Reference: https://developers.heygen.com/reference/get-current-user (guide: https://developers.heygen.com/user-profile)
// Scopes: https://developers.heygen.com/docs/api-key-permissions.md (GET /v3/users/me needs account:read)
// Errors: https://developers.heygen.com/docs/error-codes (402 insufficient_credit, 403 insufficient_api_key_scope)
//
// GET https://api.heygen.com/v3/users/me
//   headers: x-api-key: <API key>
//   200:     { "data": { "username": "…", "billing_type": "wallet" | "subscription" | "usage_based",
//              "wallet": { "currency": "usd" | "credits", "remaining_balance": 125.5,
//                          "auto_reload": { "enabled": true, "threshold_usd": 10, "amount_usd": 50 } },
//              "subscription": { "plan": "team", "credits": { "premium_credits": { "remaining": 500,
//                                "resets_at": "2024-05-01T00:00:00Z" }, "add_on_credits": { "remaining": 0 } } },
//              "usage_based": { "spending_current_usd": 42.5, "spending_cap_usd": 100,
//                               "included_credits": 4444, "remaining_credits": 4426.9 } } }
// "Exactly one of wallet / subscription / usage_based is populated depending on" billing_type.
// Errors: { "error": { "code": "…", "message": "…", "doc_url": … } }.
import Foundation

public struct HeyGenProvider: SpendProvider {
    public let id = ProviderID.heygen
    static let userURL = URL(string: "https://api.heygen.com/v3/users/me")!
    static let spendingCapID = "heygen.spending-cap"
    static let autoReloadCapID = "heygen.wallet-auto-reload-off"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Give the key the account:read scope.")
    }

    struct Reply: Decodable {
        let data: User
    }

    struct User: Decodable {
        let billingType: String?
        let wallet: Wallet?
        let subscription: Subscription?
        let usageBased: UsageBased?

        enum CodingKeys: String, CodingKey {
            case billingType = "billing_type"
            case wallet, subscription
            case usageBased = "usage_based"
        }
    }

    struct Wallet: Decodable {
        let currency: String
        let remainingBalance: FlexibleDecimal?
        let autoReload: AutoReload?

        enum CodingKeys: String, CodingKey {
            case currency
            case remainingBalance = "remaining_balance"
            case autoReload = "auto_reload"
        }
    }

    struct AutoReload: Decodable {
        let enabled: Bool
        let thresholdUSD: FlexibleDecimal?
        let amountUSD: FlexibleDecimal?

        enum CodingKeys: String, CodingKey {
            case enabled
            case thresholdUSD = "threshold_usd"
            case amountUSD = "amount_usd"
        }
    }

    struct Subscription: Decodable {
        let credits: Credits

        struct Credits: Decodable {
            let premiumCredits: Pool?
            let addOnCredits: Pool?

            enum CodingKeys: String, CodingKey {
                case premiumCredits = "premium_credits"
                case addOnCredits = "add_on_credits"
            }
        }

        struct Pool: Decodable {
            let remaining: FlexibleDecimal?
            let resetsAt: String?

            enum CodingKeys: String, CodingKey {
                case remaining
                case resetsAt = "resets_at"
            }
        }
    }

    struct UsageBased: Decodable {
        let spendingCurrentUSD: FlexibleDecimal?
        let spendingCapUSD: FlexibleDecimal?
        let includedCredits: FlexibleDecimal?
        let remainingCredits: FlexibleDecimal?

        enum CodingKeys: String, CodingKey {
            case spendingCurrentUSD = "spending_current_usd"
            case spendingCapUSD = "spending_cap_usd"
            case includedCredits = "included_credits"
            case remainingCredits = "remaining_credits"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    func read(_ credentials: ProviderCredentials) async throws -> User {
        let key = try credentials.require("apiKey")
        return try await api.get(Reply.self, Self.userURL, headers: ["x-api-key": key]).data
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let balance = try Self.balance(of: try await read(credentials))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    static func balance(of user: User) throws -> Balance {
        switch user.billingType {
        case "wallet": try walletBalance(user.wallet)
        case "usage_based": try usageBalance(user.usageBased)
        case "subscription": try subscriptionBalance(user.subscription)
        default: throw SpendError.unexpectedResponse
        }
    }

    static func walletBalance(_ wallet: Wallet?) throws -> Balance {
        guard let wallet, let remaining = wallet.remainingBalance?.value else { throw SpendError.unexpectedResponse }
        switch wallet.currency.lowercased() {
        case "usd": return .usd(remaining)
        case "credits": return Balance(remaining: remaining, unit: .units("credits"))
        default: throw SpendError.unexpectedResponse
        }
    }

    static func usageBalance(_ usage: UsageBased?) throws -> Balance {
        guard let usage else { throw SpendError.unexpectedResponse }
        if let cap = usage.spendingCapUSD?.value {
            // Without the spend so far, what's left under the cap is unknown: never assume $0 spent.
            guard let spent = usage.spendingCurrentUSD?.value else { throw SpendError.unexpectedResponse }
            return .usd(max(cap - spent, 0), kind: .allowance, limit: cap, used: spent)
        }
        if let credits = usage.remainingCredits?.value {
            return Balance(remaining: credits, unit: .units("credits"), kind: .allowance,
                           limit: usage.includedCredits?.value)
        }
        throw SpendError.planNotSupported("This HeyGen account bills by usage with no spending cap, so there's no "
            + "balance to show. Set a spending cap in HeyGen.")
    }

    static func subscriptionBalance(_ subscription: Subscription?) throws -> Balance {
        guard let credits = subscription?.credits else { throw SpendError.unexpectedResponse }
        let remaining = [credits.premiumCredits, credits.addOnCredits].compactMap { $0?.remaining?.value }
        guard !remaining.isEmpty else { throw SpendError.unexpectedResponse }
        return Balance(remaining: remaining.reduce(0, +), unit: .units("credits"), kind: .allowance,
                       resetsAt: credits.premiumCredits?.resetsAt.flatMap(ISO8601.date))
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let user = try? await read(credentials) else { return [] }
        switch user.billingType {
        case "usage_based":
            guard let usage = user.usageBased else { return [] }
            let status: CapVerification.Status
            if let cap = usage.spendingCapUSD?.value {
                guard let spent = usage.spendingCurrentUSD?.value else { return [] }
                let capText = MoneyText.string(Money(cap))
                status = spent >= cap
                    ? .enforced("HeyGen reports \(MoneyText.string(Money(spent))) spent of a \(capText) spending cap.")
                    : .on("HeyGen reports a spending cap of \(capText), with \(MoneyText.string(Money(spent))) spent.")
            } else {
                status = .off("HeyGen reports no spending cap on this usage-based account.")
            }
            return [CapVerification(capID: Self.spendingCapID, status: status, checkedAt: now)]
        case "wallet":
            guard let wallet = user.wallet else { return [] }
            let status: CapVerification.Status
            if let reload = wallet.autoReload, reload.enabled {
                var detail = "HeyGen reports auto reload is on"
                if let threshold = reload.thresholdUSD?.value, let amount = reload.amountUSD?.value {
                    detail += ": below \(MoneyText.string(Money(threshold))) it adds "
                        + MoneyText.string(Money(amount))
                }
                status = .off(detail + ", so the wallet doesn't stop spending.")
            } else {
                status = .on("HeyGen reports auto reload is off, so spending stops when the wallet runs out.")
            }
            return [CapVerification(capID: Self.autoReloadCapID, status: status, checkedAt: now)]
        default:
            return []
        }
    }
}
