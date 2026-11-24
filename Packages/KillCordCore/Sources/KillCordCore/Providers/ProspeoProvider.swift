// Prospeo credits.
// Reference: https://prospeo.io/api-docs/account-information · Auth: https://prospeo.io/api-docs/authentication
//
// GET https://api.prospeo.io/account-information
//   headers: X-KEY: <API key>
//   200:     { "error": false, "response": { "current_plan": "STARTER", "current_team_members": 1,
//              "remaining_credits": 99, "used_credits": 1, "next_quota_renewal_days": 25,
//              "next_quota_renewal_date": "2023-06-18 20:52:28+00:00" } }
// "This endpoint is free to use." Errors are { "error": true, "error_code": "…" }; an invalid key is HTTP 400
// with INVALID_API_KEY.
import Foundation

public struct ProspeoProvider: SpendProvider {
    public let id = ProviderID.prospeo
    static let accountURL = URL(string: "https://api.prospeo.io/account-information")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use an API key from app.prospeo.io/api.")
    }

    struct Reply: Decodable {
        let response: Account

        struct Account: Decodable {
            let remainingCredits: FlexibleDecimal
            let usedCredits: FlexibleDecimal?
            let nextQuotaRenewalDate: String?

            enum CodingKeys: String, CodingKey {
                case remainingCredits = "remaining_credits"
                case usedCredits = "used_credits"
                case nextQuotaRenewalDate = "next_quota_renewal_date"
            }
        }
    }

    struct Failure: Decodable {
        let errorCode: String?

        enum CodingKeys: String, CodingKey {
            case errorCode = "error_code"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let request = HTTPRequest(url: Self.accountURL, headers: ["X-KEY": key])
        let response: HTTPResponse
        do {
            response = try await api.http.send(request)
        } catch let error as SpendError {
            throw error
        } catch {
            throw SpendError.network
        }
        guard (200..<300).contains(response.status) else {
            // Prospeo answers a bad key with HTTP 400 and error_code INVALID_API_KEY, not 401.
            let code = (try? JSONDecoder().decode(Failure.self, from: response.body))?.errorCode
            if code == "INVALID_API_KEY" { throw SpendError.invalidKey }
            throw SpendError.from(status: response.status, headers: response.headers,
                                  missingScopeHint: "Use an API key from app.prospeo.io/api.", detail: code)
        }
        let account = try api.decode(Reply.self, from: response).response
        let balance = Balance(remaining: account.remainingCredits.value, unit: .units("credits"), kind: .allowance,
                              used: account.usedCredits?.value,
                              resetsAt: account.nextQuotaRenewalDate.flatMap(Self.date))
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }

    /// "2023-06-18 20:52:28+00:00".
    static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        return formatter.date(from: text)
    }
}
