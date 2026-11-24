// Runpod account balance.
// Reference: https://docs.runpod.io/api-reference-v2/billing/get-the-account-balance
// Keys: https://docs.runpod.io/get-started/credentials (All, Restricted, or Read Only)
//
// GET https://api.runpod.io/v2/billing/balance
//   headers: Authorization: Bearer <API key>   (needs the billing:read scope)
//   200:     { "balanceAmount": 42.18, "billingMode": "PREPAID" | "POSTPAID" }
// `balanceAmount` is USD. "PREPAID accounts spend from the balance. POSTPAID accounts are invoiced, so a low
// balance doesn't stop them." An organization with no billing account answers 404.
// Errors are problem+json: { "title": "Forbidden", "status": 403, "detail": "access denied" }.
import Foundation

public struct RunpodProvider: SpendProvider {
    public let id = ProviderID.runpod
    static let balanceURL = URL(string: "https://api.runpod.io/v2/billing/balance")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Create a Read Only key, or a Restricted key with "
            + "the billing:read scope.")
    }

    struct BillingBalance: Decodable {
        let balanceAmount: FlexibleDecimal
        let billingMode: String
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let reply = try await api.get(BillingBalance.self, Self.balanceURL, headers: ["Authorization": "Bearer \(key)"])
        switch reply.billingMode.uppercased() {
        case "PREPAID":
            let balance = Balance.usd(reply.balanceAmount.value)
            return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
        case "POSTPAID":
            throw SpendError.planNotSupported("Runpod invoices this account after use, so its balance doesn't "
                + "limit spending. Kill Cord shows prepaid Runpod balances only.")
        default:
            throw SpendError.unexpectedResponse
        }
    }
}
