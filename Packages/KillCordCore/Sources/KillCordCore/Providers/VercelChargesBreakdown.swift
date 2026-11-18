// Vercel spend by project, from the FOCUS billing charges (Kill Cord Teams, unit 9).
// Reference: https://vercel.com/docs/rest-api/billing/list-focus-billing-charges (read 2026-11-18)
//
// GET https://api.vercel.com/v1/billing/charges?from=…&to=…&teamId=…   (the same call VercelProvider makes)
//   from: inclusive ISO 8601 UTC; to: exclusive; 1-day granularity; "a maximum date range of 1 year".
//   200: application/jsonl, one FOCUS v1.3 charge per line: BilledCost (number), BillingCurrency ("USD"),
//        ChargePeriodStart, ChargePeriodEnd (exclusive), ServiceName, SubAccountId (the team), …,
//        Tags: "Charge metadata including the Vercel ProjectId and ProjectName information".
// A charge with no project in its Tags (team-level charges) is Unassigned. Vercel has no per-user or per-key
// data: a "person" for Vercel spend means whoever an admin assigns the project to.
//
// UNVERIFIED:
// - The exact Tags key spelling. The schema describes Tags as an object of strings carrying "the Vercel
//   ProjectId and ProjectName information" but lists no keys, and its example shows `"Tags": "value"`. Kill Cord
//   reads `ProjectId` and `ProjectName`, accepts Tags as an object or as a JSON-encoded string, and treats
//   anything else as no project (Unassigned, never guessed). Check on a real team.
// - BilledCost is typed as a number but shown as a string in the example, so both are accepted (as in
//   VercelProvider).
import Foundation

public struct VercelChargesBreakdown: Sendable {
    /// The API's documented maximum range per request.
    static let maxDays = 365

    private let api: APIRequester
    private let vercel: VercelProvider

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Scope the token to the team, and make sure your role "
            + "on the team can see billing.")
        vercel = VercelProvider(http: http)
    }

    struct Charge: Decodable {
        let billedCost: FlexibleDecimal
        let billingCurrency: String?
        let chargePeriodStart: String
        let chargePeriodEnd: String?
        let tags: [String: String]?

        enum CodingKeys: String, CodingKey {
            case billedCost = "BilledCost"
            case billingCurrency = "BillingCurrency"
            case chargePeriodStart = "ChargePeriodStart"
            case chargePeriodEnd = "ChargePeriodEnd"
            case tags = "Tags"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            billedCost = try container.decode(FlexibleDecimal.self, forKey: .billedCost)
            billingCurrency = try container.decodeIfPresent(String.self, forKey: .billingCurrency)
            chargePeriodStart = try container.decode(String.self, forKey: .chargePeriodStart)
            chargePeriodEnd = try container.decodeIfPresent(String.self, forKey: .chargePeriodEnd)
            if let object = try? container.decodeIfPresent([String: String].self, forKey: .tags) {
                tags = object
            } else if let text = try? container.decodeIfPresent(String.self, forKey: .tags),
                      let object = try? JSONDecoder().decode([String: String].self, from: Data(text.utf8)) {
                tags = object
            } else {
                tags = nil
            }
        }

        var projectID: String? {
            guard let id = tags?["ProjectId"]?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
            return id
        }
    }

    static func parse(_ body: Data) throws -> [Charge] {
        guard let text = String(data: body, encoding: .utf8) else { throw SpendError.unexpectedResponse }
        return try text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            do {
                return try JSONDecoder().decode(Charge.self, from: Data(trimmed.utf8))
            } catch {
                throw SpendError.unexpectedResponse
            }
        }
    }

    /// Builds the report from charges. The provider total is the sum of every charge in the same response, so a
    /// charge that failed to map to a row would show as a gap instead of disappearing.
    static func report(_ charges: [Charge], range: DateInterval) throws -> AttributionReport {
        var rows: [AttributedSpend] = []
        var total = MoneyTotals()
        var units: [String: AttributionUnit] = [:]
        for charge in charges {
            guard let start = ISO8601.date(charge.chargePeriodStart) else { throw SpendError.unexpectedResponse }
            let end = charge.chargePeriodEnd.flatMap(ISO8601.date) ?? start.addingTimeInterval(86_400)
            let money = Money(charge.billedCost.value, Currency(charge.billingCurrency ?? "USD"))
            total.add(money)
            let unit = charge.projectID.map { AttributionUnitRef(kind: .project, externalID: $0) }
            if let id = charge.projectID, units[id] == nil {
                units[id] = AttributionUnit(provider: .vercel, kind: .project, externalID: id,
                                            label: charge.tags?["ProjectName"])
            }
            rows.append(AttributedSpend(bucketStart: start, bucketEnd: end, unit: unit, amount: money))
        }
        return AttributionReport(provider: .vercel, dimension: .project, rangeStart: range.start,
                                 rangeEnd: range.end, rows: rows, providerTotal: total, dataRefreshedAt: nil,
                                 meaningVerified: true, units: units.values.sorted { $0.externalID < $1.externalID })
    }

    /// Spend by project for whole UTC days in [start, end), split into requests of at most a year.
    public func projectReport(_ credentials: ProviderCredentials, from start: Date, to end: Date,
                              now: Date) async throws -> AttributionReport {
        let token = try credentials.require("token")
        let lower = AttributionWindows.utcDayStart(start)
        let upper = min(AttributionWindows.utcDayStart(end.addingTimeInterval(86_399)),
                        AttributionWindows.utcDayStart(now).addingTimeInterval(86_400))
        guard upper > lower else { throw AttributionRangeError.empty }
        var charges: [Charge] = []
        for window in AttributionWindows.split(start: lower, end: upper, maxDays: Self.maxDays) {
            let response = try await api.send(HTTPRequest(
                url: vercel.url(from: window.start, to: window.end, teamID: credentials["teamID"]),
                headers: vercel.headers(token)
            ))
            charges += try Self.parse(response.body)
        }
        return try Self.report(charges, range: DateInterval(start: lower, end: upper))
    }
}
