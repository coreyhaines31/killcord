import Foundation
@testable import KillCordCore
import Testing

@Suite struct TwilioSubaccountBreakdownTests {
    static let main = "ACaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    static let marketing = "ACbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    static let closed = "ACcccccccccccccccccccccccccccccccc"

    func client(allTotal: String = "twilio-month-all.json") throws -> MockHTTPClient {
        let accounts = try json("twilio-accounts.json")
        let all = try json(allTotal)
        let mainOwn = try json("twilio-month-main-own.json")
        let marketing = try json("twilio-month-marketing.json")
        let empty = try json("twilio-month-empty.json")
        return MockHTTPClient { request in
            if request.path == "/2010-04-01/Accounts.json" { return accounts }
            let own = request.query("IncludeSubaccounts") == ["false"]
            switch request.path {
            case "/2010-04-01/Accounts/\(Self.main)/Usage/Records/ThisMonth.json": return own ? mainOwn : all
            case "/2010-04-01/Accounts/\(Self.marketing)/Usage/Records/ThisMonth.json": return marketing
            default: return empty
            }
        }
    }

    @Test func readsEveryAccountWithGetsAndBasicAuthOnly() async throws {
        let http = try client()
        _ = try await TwilioSubaccountBreakdown(http: http).subaccountReport(
            FakeKeys.credentials(.twilio), period: .thisMonth, now: testNow)
        // The account list, the all-accounts total, and each account's own total.
        #expect(http.requests.count == 5)
        for request in http.requests {
            #expect(request.method == .get)
            #expect(request.url.host == "api.twilio.com")
            #expect(request.headers["Authorization"]?.hasPrefix("Basic ") == true)
            #expect(!request.url.absoluteString.contains(FakeKeys.twilio))
        }
        #expect(http.requests[0].query("PageSize") == ["1000"])
        let usage = http.requests.dropFirst()
        #expect(usage.allSatisfy { $0.query("Category") == ["totalprice"] })
        #expect(usage.filter { $0.query("IncludeSubaccounts") == ["true"] }.count == 1)
    }

    @Test func reconcilesBySubaccountToTheCent() async throws {
        let report = try await TwilioSubaccountBreakdown(http: try client()).subaccountReport(
            FakeKeys.credentials(.twilio), period: .thisMonth, now: testNow)
        #expect(report.dimension == .subaccount)
        #expect(report.providerTotal.amount(in: .usd) == usd("25.12345"))
        #expect(report.reconciles)
        let unit = { AttributionUnitRef(kind: .subaccount, externalID: $0) }
        #expect(report.byUnit[unit(Self.main)]?.amount(in: .usd) == usd("10.00001"))
        // `price` as a string is read the same as a number.
        #expect(report.byUnit[unit(Self.marketing)]?.amount(in: .usd) == usd("15.12344"))
        #expect(report.byUnit[unit(Self.closed)] == nil)
        #expect(report.unassigned.amounts.isEmpty)
        #expect(report.rangeStart == ISO8601.date("2026-11-01T00:00:00Z"))
        #expect(report.rangeEnd == ISO8601.date("2026-11-16T00:00:00Z"))
        #expect(report.dataRefreshedAt == ISO8601.date("2026-11-15T18:02:11Z"))
        let labels = report.units.map { "\($0.externalID):\($0.label ?? "")" }
        #expect(labels == ["\(Self.main):Main account (Acme)", "\(Self.marketing):Marketing", "\(Self.closed):Old pilot"])
        #expect(report.units.first { $0.externalID == Self.closed }?.status == "closed")
    }

    @Test func aTotalThatDisagreesIsReportedNotHidden() async throws {
        // The all-accounts total says $10.00001, but the parts add up to $25.12345.
        let report = try await TwilioSubaccountBreakdown(http: try client(allTotal: "twilio-month-main-own.json"))
            .subaccountReport(FakeKeys.credentials(.twilio), period: .thisMonth, now: testNow)
        #expect(!report.reconciles)
        #expect(report.gap.amount(in: .usd) == usd("-15.12344"))
    }

    @Test func refusesAPageLinkThatLeavesTwilio() async throws {
        let hostile = HTTPResponse(status: 200, json: """
        {"accounts":[],"next_page_uri":"https://evil.example/2010-04-01/Accounts.json"}
        """)
        let breakdown = TwilioSubaccountBreakdown(http: MockHTTPClient { _ in hostile })
        await #expect(throws: SpendError.unexpectedResponse) {
            try await breakdown.subaccountReport(FakeKeys.credentials(.twilio), period: .thisMonth, now: testNow)
        }
    }

    @Test func errorsNeverContainTheSecret() async throws {
        for response in SecretSafetyTests.hostileResponses(echo: FakeKeys.twilio) {
            do {
                _ = try await TwilioSubaccountBreakdown(http: MockHTTPClient { _ in response }).subaccountReport(
                    FakeKeys.credentials(.twilio), period: .thisMonth, now: testNow)
                Issue.record("expected an error for status \(response.status)")
            } catch {
                #expect(!String(describing: error).contains(FakeKeys.twilio))
            }
        }
    }
}
