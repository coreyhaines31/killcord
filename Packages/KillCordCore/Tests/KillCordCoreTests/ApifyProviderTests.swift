// swiftlint:disable line_length
// Fixtures follow Apify's documented response: https://docs.apify.com/api/v2/users-me-limits-get
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ApifyProviderTests {
    @Test func readsTheCyclesSpendAndWhatsLeftOfTheLimit() async throws {
        let http = MockHTTPClient(routes: ["/v2/users/me/limits": try json("apify-users-me-limits.json")])
        let snapshot = try await ApifyProvider(http: http).fetchSpend(FakeKeys.credentials(.apify), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url.absoluteString == "https://api.apify.com/v2/users/me/limits")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.apify)")
        #expect(snapshot.month == usd("43.27"))
        #expect(snapshot.today == nil)
        #expect(snapshot.monthKind == .billingPeriod(start: ISO8601.date("2026-11-02T00:00:00.000Z")!))
        #expect(snapshot.balance == .usd(decimal("256.73"), kind: .allowance, limit: 300,
                                         resetsAt: ISO8601.date("2026-12-01T23:59:59.999Z")))
    }

    @Test func monthSpendCountsTowardTotalsButTodayDoesNot() {
        #expect(ProviderID.apify.info.capability.countsMonth)
        #expect(!ProviderID.apify.info.capability.countsToday)
    }

    @Test func confirmsTheUsageLimitFromTheAPI() async throws {
        let http = MockHTTPClient(routes: ["/v2/users/me/limits": try json("apify-users-me-limits.json")])
        let results = await ApifyProvider(http: http).verifyCaps(FakeKeys.credentials(.apify), now: testNow)
        #expect(results.map(\.capID) == [ApifyProvider.usageLimitCapID])
        #expect(results.first?.status == .on("Apify reports a usage limit of $300.00 this cycle. Past it, Apify suspends its services."))
        #expect(CapsCatalog.control(ApifyProvider.usageLimitCapID)?.verification == .api)
    }

    @Test func aReachedLimitIsEnforced() async throws {
        let body = #"{"data":{"monthlyUsageCycle":{"startAt":"2026-11-02T00:00:00.000Z","endAt":"2026-12-01T23:59:59.999Z"},"limits":{"maxMonthlyUsageUsd":100},"current":{"monthlyUsageUsd":100.4}}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await ApifyProvider(http: http).fetchSpend(FakeKeys.credentials(.apify), now: testNow)
        #expect(snapshot.balance?.remaining == 0)
        let results = await ApifyProvider(http: http).verifyCaps(FakeKeys.credentials(.apify), now: testNow)
        guard case .enforced = results.first?.status else {
            Issue.record("Expected enforced, got \(String(describing: results.first?.status))")
            return
        }
    }

    @Test func showsApifysOwnMessage() async {
        let body = #"{"error":{"type":"insufficient-permissions","message":"You do not have permission to perform this action."}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "You do not have permission to perform this action.")) {
            try await ApifyProvider(http: http).fetchSpend(FakeKeys.credentials(.apify), now: testNow)
        }
    }

    @Test func aFailedCapCheckIsSkipped() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 503) }
        #expect(await ApifyProvider(http: http).verifyCaps(FakeKeys.credentials(.apify), now: testNow).isEmpty)
    }
}
// swiftlint:enable line_length
