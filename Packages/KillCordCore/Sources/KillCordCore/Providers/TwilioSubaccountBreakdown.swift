// Twilio spend by subaccount (Kill Cord Teams, unit 9). Read 2026-11-18:
//   Accounts:      https://www.twilio.com/docs/iam/api/account
//   Subaccounts:   https://www.twilio.com/docs/iam/api/subaccounts
//   Usage records: https://www.twilio.com/docs/usage/api/usage-record
//
// GET https://api.twilio.com/2010-04-01/Accounts.json?PageSize=1000
//   "Retrieve all Account resources that belong to the account making the API request, including its
//   subaccounts." 200: { accounts: [{ sid, friendly_name, status, owner_account_sid, type }], next_page_uri }.
//   "To create, update, or list subaccounts, use a Main API key."
// GET https://api.twilio.com/2010-04-01/Accounts/{Sid}/Usage/Records/{ThisMonth|LastMonth}.json
//       ?Category=totalprice&IncludeSubaccounts=false
//   IncludeSubaccounts: "Whether to include usage from the master account and all its subaccounts." Default true.
//   "Your main account credentials will allow you to access resources for any of your subaccounts", and "Twilio
//   bills all subaccount usage directly to your main account."
//
// So: list the accounts, read each one's own total (IncludeSubaccounts=false), and read the main account's total
// with subaccounts included as the provider's total. The main account's own usage is one more unit, so an admin
// can assign it like any subaccount. Twilio has no per-user or per-key cost: a "person" here is whoever an admin
// assigns the subaccount to. Every call is a GET with HTTP Basic auth (TwilioProvider's headers).
//
// UNVERIFIED: whether a Standard (not Main) API key may read subaccounts' usage. The docs only say listing needs
// a Main API key; a refusal surfaces as Twilio's own missing-access error.
import Foundation

public struct TwilioSubaccountBreakdown: Sendable {
    public enum Period: String, Sendable {
        case thisMonth = "ThisMonth"
        case lastMonth = "LastMonth"
    }

    static let root = URL(string: "https://api.twilio.com")!
    static let maxPages = 20
    static let maxAccounts = 500

    private let api: APIRequester
    private let twilio: TwilioProvider

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a Main API key (or the main account's Auth Token): "
            + "Twilio only lets the main account read its subaccounts.")
        twilio = TwilioProvider(http: http)
    }

    struct AccountList: Decodable {
        struct Account: Decodable {
            let sid: String
            let friendlyName: String?
            let status: String?
            let ownerAccountSid: String?

            enum CodingKeys: String, CodingKey {
                case sid
                case friendlyName = "friendly_name"
                case status
                case ownerAccountSid = "owner_account_sid"
            }
        }

        let accounts: [Account]
        let nextPageURI: String?

        enum CodingKeys: String, CodingKey {
            case accounts
            case nextPageURI = "next_page_uri"
        }
    }

    struct RecordList: Decodable {
        struct Record: Decodable {
            let accountSid: String?
            let category: String
            let price: FlexibleDecimal?
            let priceUnit: String?
            let startDate: String?
            let endDate: String?
            let asOf: String?

            enum CodingKeys: String, CodingKey {
                case accountSid = "account_sid"
                case category
                case price
                case priceUnit = "price_unit"
                case startDate = "start_date"
                case endDate = "end_date"
                case asOf = "as_of"
            }
        }

        let usageRecords: [Record]

        enum CodingKeys: String, CodingKey {
            case usageRecords = "usage_records"
        }
    }

    static func isAccountSID(_ text: String) -> Bool {
        text.count == 34 && text.hasPrefix("AC") && FieldFormat.isIdentifier(text)
    }

    /// The main account and its subaccounts. Pages follow `next_page_uri` on api.twilio.com only.
    func accounts(_ headers: [String: String]) async throws -> [AccountList.Account] {
        var url = Self.root.appendingPathComponent("2010-04-01/Accounts.json")
            .adding([URLQueryItem(name: "PageSize", value: "1000")])
        var accounts: [AccountList.Account] = []
        for _ in 0..<Self.maxPages {
            let page = try await api.get(AccountList.self, url, headers: headers)
            accounts += page.accounts
            guard let next = page.nextPageURI, !next.isEmpty else { break }
            // A relative path from Twilio; refuse anything that would leave api.twilio.com.
            guard next.hasPrefix("/2010-04-01/Accounts.json"), let nextURL = URL(string: next, relativeTo: Self.root)
            else { throw SpendError.unexpectedResponse }
            url = nextURL.absoluteURL
        }
        guard accounts.count <= Self.maxAccounts, accounts.allSatisfy({ Self.isAccountSID($0.sid) }) else {
            throw SpendError.unexpectedResponse
        }
        return accounts
    }

    func total(sid: String, period: Period, includeSubaccounts: Bool,
               headers: [String: String]) async throws -> RecordList.Record? {
        let url = Self.root.appendingPathComponent("2010-04-01/Accounts").appendingPathComponent(sid)
            .appendingPathComponent("Usage/Records/\(period.rawValue).json")
            .adding([URLQueryItem(name: "Category", value: "totalprice"),
                     URLQueryItem(name: "IncludeSubaccounts", value: includeSubaccounts ? "true" : "false")])
        let list = try await api.get(RecordList.self, url, headers: headers)
        return list.usageRecords.first { $0.category == "totalprice" }
    }

    static func money(_ record: RecordList.Record?) -> Money {
        guard let record else { return .zero() }
        return Money(record.price?.value ?? 0, Currency(record.priceUnit ?? "usd"))
    }

    /// Spend for the period by account: the main account's own usage and each subaccount's.
    public func subaccountReport(_ credentials: ProviderCredentials, period: Period,
                                 now: Date) async throws -> AttributionReport {
        let mainSID = try credentials.require("accountSID")
        guard Self.isAccountSID(mainSID) else { throw SpendError.notConfigured }
        let headers = try twilio.headers(credentials)
        var accounts = try await accounts(headers)
        if !accounts.contains(where: { $0.sid == mainSID }) {
            accounts.insert(AccountList.Account(sid: mainSID, friendlyName: nil, status: nil, ownerAccountSid: nil),
                            at: 0)
        }

        let all = try await total(sid: mainSID, period: period, includeSubaccounts: true, headers: headers)
        let (rangeStart, rangeEnd) = Self.range(all, period: period, now: now)
        var rows: [AttributedSpend] = []
        var units: [AttributionUnit] = []
        for account in accounts {
            let own = try await total(sid: account.sid, period: period, includeSubaccounts: false, headers: headers)
            let isMain = account.sid == mainSID
            units.append(AttributionUnit(provider: .twilio, kind: .subaccount, externalID: account.sid,
                                         label: isMain ? "Main account" + (account.friendlyName.map { " (\($0))" } ?? "")
                                             : account.friendlyName,
                                         parentID: isMain ? nil : mainSID, status: account.status))
            let amount = Self.money(own)
            guard amount.amount != 0 else { continue }
            rows.append(AttributedSpend(bucketStart: rangeStart, bucketEnd: rangeEnd,
                                        unit: AttributionUnitRef(kind: .subaccount, externalID: account.sid),
                                        amount: amount))
        }
        return AttributionReport(provider: .twilio, dimension: .subaccount, rangeStart: rangeStart,
                                 rangeEnd: rangeEnd, rows: rows, providerTotal: MoneyTotals([Self.money(all)]),
                                 dataRefreshedAt: all?.asOf.flatMap(ISO8601.date), meaningVerified: true, units: units)
    }

    /// Twilio's own dates for the period when it reports them (GMT), else the calendar month.
    static func range(_ record: RecordList.Record?, period: Period, now: Date) -> (Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: now)
        let thisMonth = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1))!
        let start = period == .thisMonth ? thisMonth : calendar.date(byAdding: .month, value: -1, to: thisMonth)!
        let fallbackEnd = period == .thisMonth ? AttributionWindows.utcDayStart(now).addingTimeInterval(86_400)
            : thisMonth
        func day(_ text: String?) -> Date? { text.flatMap { ISO8601.date($0 + "T00:00:00Z") } }
        let lower = day(record?.startDate) ?? start
        let upper = day(record?.endDate).map { $0.addingTimeInterval(86_400) } ?? fallbackEnd
        return (lower, upper)
    }
}
