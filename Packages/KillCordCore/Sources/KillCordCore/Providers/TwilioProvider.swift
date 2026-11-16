// Twilio REST API, Usage Records and Usage Triggers.
// Usage records: https://www.twilio.com/docs/usage/api/usage-record
// Usage triggers: https://www.twilio.com/docs/usage/api/usage-trigger
//
// GET https://api.twilio.com/2010-04-01/Accounts/{AccountSid}/Usage/Records/Today.json?Category=totalprice
// GET https://api.twilio.com/2010-04-01/Accounts/{AccountSid}/Usage/Records/ThisMonth.json?Category=totalprice
//   auth:  HTTP Basic, API key SID and secret (recommended) or Account SID and Auth Token
//   200:   { usage_records: [{ category: "totalprice", price: "12.34567", price_unit: "usd",
//            as_of: "2026-11-16T14:02:11+00:00", start_date, end_date, … }], next_page_uri, … }
// `totalprice` is the account's total cost. `price` is documented as a number but shown as a string in the
// examples, so both are accepted. Dates are GMT. Subaccounts are included by default.
//
// GET https://api.twilio.com/2010-04-01/Accounts/{AccountSid}/Usage/Triggers.json?UsageCategory=totalprice
//   200: { usage_triggers: [{ usage_category, trigger_by: "price", trigger_value, recurring, … }] }
// A trigger calls a webhook when usage crosses a value. It's an alert, not a stop.
import Foundation

public struct TwilioProvider: SpendProvider {
    public let id = ProviderID.twilio
    static let base = URL(string: "https://api.twilio.com/2010-04-01/Accounts/")!
    public static let triggerCapID = "twilio.usage-trigger"

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a Standard API key (Restricted keys may not read "
            + "usage), or the Auth Token.")
    }

    struct RecordList: Decodable {
        struct Record: Decodable {
            let category: String
            let price: FlexibleDecimal?
            let priceUnit: String?
            let asOf: String?

            enum CodingKeys: String, CodingKey {
                case category
                case price
                case priceUnit = "price_unit"
                case asOf = "as_of"
            }
        }

        let usageRecords: [Record]

        enum CodingKeys: String, CodingKey {
            case usageRecords = "usage_records"
        }
    }

    struct TriggerList: Decodable {
        struct Trigger: Decodable {
            let usageCategory: String?
            let triggerBy: String?
            let triggerValue: String?
            let recurring: String?

            enum CodingKeys: String, CodingKey {
                case usageCategory = "usage_category"
                case triggerBy = "trigger_by"
                case triggerValue = "trigger_value"
                case recurring
            }
        }

        let usageTriggers: [Trigger]

        enum CodingKeys: String, CodingKey {
            case usageTriggers = "usage_triggers"
        }
    }

    func accountURL(_ credentials: ProviderCredentials, _ path: String, query: [URLQueryItem]) throws -> URL {
        let sid = try credentials.require("accountSID")
        guard sid.hasPrefix("AC"), FieldFormat.isIdentifier(sid) else { throw SpendError.notConfigured }
        return Self.base.appendingPathComponent(sid).appendingPathComponent(path).adding(query)
    }

    func headers(_ credentials: ProviderCredentials) throws -> [String: String] {
        let user = try credentials["apiKeySID"] ?? credentials.require("accountSID")
        let secret = try credentials.require("secret")
        let basic = Data("\(user):\(secret)".utf8).base64EncodedString()
        return ["Authorization": "Basic \(basic)", "accept": "application/json"]
    }

    func total(_ credentials: ProviderCredentials, period: String) async throws -> (Money, Date?) {
        let url = try accountURL(credentials, "Usage/Records/\(period).json",
                                 query: [URLQueryItem(name: "Category", value: "totalprice")])
        let list = try await api.get(RecordList.self, url, headers: try headers(credentials))
        guard let record = list.usageRecords.first(where: { $0.category == "totalprice" }) else {
            // No record means no billable usage in the period.
            return (.zero(), nil)
        }
        let money = Money(record.price?.value ?? 0, Currency(record.priceUnit ?? "usd"))
        return (money, record.asOf.flatMap(ISO8601.date))
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await total(credentials, period: "Today")
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let (today, todayAsOf) = try await total(credentials, period: "Today")
        let (month, monthAsOf) = try await total(credentials, period: "ThisMonth")
        guard today.currency == month.currency else { throw SpendError.unexpectedResponse }
        return SpendSnapshot(provider: id, today: today, month: month,
                             dataAsOf: [todayAsOf, monthAsOf].compactMap { $0 }.min(), fetchedAt: now)
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let url = try? accountURL(credentials, "Usage/Triggers.json",
                                        query: [URLQueryItem(name: "UsageCategory", value: "totalprice")]),
              let headers = try? headers(credentials),
              let list = try? await api.get(TriggerList.self, url, headers: headers)
        else { return [] }
        let spend = list.usageTriggers.filter { $0.usageCategory == "totalprice" && $0.triggerBy == "price" }
        let status: CapVerification.Status
        if spend.isEmpty {
            status = .off("Twilio reports no usage trigger on total spend.")
        } else {
            let list = spend.map { trigger in
                let value = trigger.triggerValue.flatMap { Money($0) }.map(MoneyText.string) ?? "a set amount"
                return "\(value) \(trigger.recurring ?? "")".trimmingCharacters(in: .whitespaces)
            }
            status = .on("Twilio reports a usage trigger on total spend: \(list.joined(separator: ", ")). "
                + "Triggers alert; they don't stop usage.")
        }
        return [CapVerification(capID: Self.triggerCapID, status: status, checkedAt: now)]
    }
}
