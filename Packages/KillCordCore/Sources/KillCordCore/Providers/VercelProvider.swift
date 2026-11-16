// Vercel REST API, billing charges (FOCUS v1.3).
// Reference: https://vercel.com/docs/rest-api/billing/list-focus-billing-charges
// Announcement: https://vercel.com/changelog/access-billing-usage-cost-data-api
// Spend Management: https://vercel.com/docs/spend-management
//
// GET https://api.vercel.com/v1/billing/charges
//   headers: Authorization: Bearer <access token>
//   query:   from (inclusive ISO 8601, UTC, required), to (exclusive, required), teamId (optional)
//   200:     Content-Type: application/jsonl, one FOCUS charge per line:
//            { "BilledCost": 1.42, "BillingCurrency": "USD", "ChargePeriodStart": "2026-11-14T00:00:00Z",
//              "ChargePeriodEnd": "2026-11-15T00:00:00Z", "ServiceName": "…", … }
// Charges are daily. The schema types BilledCost as a number in USD, but the docs' example shows a string,
// so both are accepted. Data lag isn't documented, so a day with no rows yet is "not reported", not $0.
// There's no API for Spend Management settings, so the Vercel caps are self-reported.
import Foundation

public struct VercelProvider: SpendProvider {
    public let id = ProviderID.vercel
    static let chargesURL = URL(string: "https://api.vercel.com/v1/billing/charges")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Scope the token to the team, and make sure your role "
            + "on the team can see billing (Owner, Member, Developer, Billing, or Viewer).")
    }

    struct Charge: Decodable {
        let billedCost: FlexibleDecimal
        let billingCurrency: String?
        let chargePeriodStart: String

        enum CodingKeys: String, CodingKey {
            case billedCost = "BilledCost"
            case billingCurrency = "BillingCurrency"
            case chargePeriodStart = "ChargePeriodStart"
        }
    }

    func url(from start: Date, to end: Date, teamID: String?) -> URL {
        var items = [
            URLQueryItem(name: "from", value: ISO8601.string(start)),
            URLQueryItem(name: "to", value: ISO8601.string(end))
        ]
        if let teamID { items.append(URLQueryItem(name: "teamId", value: teamID)) }
        return Self.chargesURL.adding(items)
    }

    func headers(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "accept": "application/jsonl, application/json"]
    }

    /// Parses newline-delimited JSON, skipping blank lines.
    static func parse(_ body: Data) throws -> [Charge] {
        guard let text = String(data: body, encoding: .utf8) else { throw SpendError.unexpectedResponse }
        let decoder = JSONDecoder()
        return try text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            do {
                return try decoder.decode(Charge.self, from: Data(trimmed.utf8))
            } catch {
                throw SpendError.unexpectedResponse
            }
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        let token = try credentials.require("token")
        let window = window(now)
        let response = try await api.send(HTTPRequest(
            url: url(from: window.dayStart, to: window.dayEnd, teamID: credentials["teamID"]), headers: headers(token)
        ))
        _ = try Self.parse(response.body)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let token = try credentials.require("token")
        let window = window(now)
        // `to` is exclusive, so the start of tomorrow covers today's daily row.
        let response = try await api.send(HTTPRequest(
            url: url(from: window.monthStart, to: window.dayEnd, teamID: credentials["teamID"]),
            headers: headers(token)
        ))
        let charges = try Self.parse(response.body)
        return try FOCUSTotals.snapshot(
            provider: id, rows: charges.map { ($0.billedCost.value, $0.billingCurrency, $0.chargePeriodStart) },
            window: window, monthKind: .calendarMonth, now: now
        )
    }
}

/// Totals for FOCUS-style daily charge rows (Vercel, Cloudflare).
enum FOCUSTotals {
    static func snapshot(provider: ProviderID, rows: [(Decimal, String?, String)], window: BillingWindow,
                         monthKind: SpendSnapshot.MonthKind, now: Date) throws -> SpendSnapshot {
        var month = Money.zero()
        var today: Money?
        for (amount, currencyCode, periodStart) in rows {
            guard let start = ISO8601.date(periodStart) else { throw SpendError.unexpectedResponse }
            let money = Money(amount, Currency(currencyCode ?? "USD"))
            guard money.currency == .usd else { throw SpendError.unexpectedResponse }
            month = month + money
            if start >= window.dayStart { today = (today ?? .zero()) + money }
        }
        return SpendSnapshot(provider: provider, today: today, month: month, monthKind: monthKind, fetchedAt: now)
    }
}
