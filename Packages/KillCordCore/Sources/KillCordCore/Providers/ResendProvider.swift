// Resend emails used this month, from the quota headers Resend sends with API responses.
// Quotas: https://resend.com/docs/api-reference/rate-limit ("the API returns headers that track your email sending
// quotas": `x-resend-monthly-quota`, "Your used monthly email sending quota", and `x-resend-daily-quota`, "Only sent
// to free plan users").
// Request: https://resend.com/docs/api-reference/domains/list-domains. Keys:
// https://resend.com/docs/api-reference/api-keys/create-api-key (a sending-access key "Can only send emails" and gets
// 401 `restricted_api_key` on anything else, so reading needs a full-access key).
//
// GET https://api.resend.com/domains?limit=1   (a read that changes nothing; its body is ignored)
//   headers: Authorization: Bearer re_…, User-Agent (Resend requires one)
// The quota headers are used counts only: Resend's API doesn't report the plan's quota. Both sent and received emails
// count. Errors: { "name": "…", "statusCode": 401, "message": "…" }.
import Foundation

public struct ResendProvider: SpendProvider {
    public let id = ProviderID.resend
    static let domainsURL = URL(string: "https://api.resend.com/domains?limit=1")!
    static let missingScopeHint = "Use a key with Full access. A Sending access key can only send emails."

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: Self.missingScopeHint)
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let request = HTTPRequest(url: Self.domainsURL, headers: ["Authorization": "Bearer \(key)",
                                                                  "User-Agent": "KillCord"])
        let response = try await send(request)
        guard let monthly = Self.count(response.header("x-resend-monthly-quota")) else {
            throw SpendError.unexpectedResponse
        }
        var usage = [UsageMetric(id: "monthEmails", name: "Emails this month", value: monthly, unit: "emails")]
        if let daily = Self.count(response.header("x-resend-daily-quota")) {
            usage.append(UsageMetric(id: "dayEmails", name: "Emails today", value: daily, unit: "emails"))
        }
        return SpendSnapshot(provider: id, today: nil, month: nil, usage: usage, fetchedAt: now)
    }

    /// Sends through `APIRequester`'s mapping, except that Resend's 401 `restricted_api_key` (a Sending access key)
    /// becomes a missing-scope error that says which key to use, not "key rejected".
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await api.http.send(request)
        } catch let error as SpendError {
            throw error
        } catch {
            throw SpendError.network
        }
        if response.status == 401, String(bytes: response.body, encoding: .utf8)?.contains("restricted_api_key") == true {
            throw SpendError.missingScope(hint: Self.missingScopeHint)
        }
        guard (200..<300).contains(response.status) else {
            throw SpendError.from(status: response.status, headers: response.headers,
                                  missingScopeHint: Self.missingScopeHint,
                                  detail: ProviderErrorDetail.message(in: response.body, sentWith: request))
        }
        return response
    }

    /// A whole, non-negative count.
    static func count(_ header: String?) -> Decimal? {
        guard let text = header?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
              text.allSatisfy(\.isASCIIDigit) else { return nil }
        return Decimal(string: text)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
