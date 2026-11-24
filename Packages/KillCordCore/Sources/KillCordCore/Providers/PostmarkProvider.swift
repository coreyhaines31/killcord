// Postmark emails sent today and this month by one server. Postmark reports counts, not money.
// Reference: https://postmarkapp.com/developer/api/stats-api ("Get sent counts"). Errors:
// https://postmarkapp.com/developer/api/overview ({ "ErrorCode": 10, "Message": "…" }).
//
// GET https://api.postmarkapp.com/stats/outbound/sends?fromdate=YYYY-MM-DD&todate=YYYY-MM-DD
//   headers: Accept: application/json, X-Postmark-Server-Token: <server token>   ("requires server level privileges")
//   200:     { "Days": [{ "Date": "2014-01-01", "Sent": 140 }, …], "Sent": 615 }
// Both dates are inclusive. "Days that didn't produce statistics won't appear." This counts one server's outbound
// email; Postmark bills sent and received email across the account, on a cycle that starts on the activation date.
import Foundation

public struct PostmarkProvider: SpendProvider {
    public let id = ProviderID.postmark
    static let sendsURL = URL(string: "https://api.postmarkapp.com/stats/outbound/sends")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a Server API token from the server's API Tokens "
            + "tab. An Account token can't read stats.")
    }

    struct Sends: Decodable {
        let days: [Day]?
        let sent: FlexibleDecimal

        enum CodingKeys: String, CodingKey {
            case days = "Days"
            case sent = "Sent"
        }

        struct Day: Decodable {
            let date: String
            let sent: FlexibleDecimal

            enum CodingKeys: String, CodingKey {
                case date = "Date"
                case sent = "Sent"
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let token = try credentials.require("apiKey")
        let window = window(now)
        let url = Self.sendsURL.adding([URLQueryItem(name: "fromdate", value: window.monthKey + "-01"),
                                        URLQueryItem(name: "todate", value: window.dayKey)])
        let sends = try await api.get(Sends.self, url, headers: ["Accept": "application/json",
                                                                  "X-Postmark-Server-Token": token])
        let today = sends.days?.first { $0.date.prefix(10) == window.dayKey }?.sent.value ?? 0
        let usage = [
            UsageMetric(id: "monthSent", name: "Emails sent this month", value: sends.sent.value, unit: "emails"),
            UsageMetric(id: "daySent", name: "Emails sent today", value: today, unit: "emails")
        ]
        return SpendSnapshot(provider: id, today: nil, month: nil, usage: usage, fetchedAt: now)
    }
}
