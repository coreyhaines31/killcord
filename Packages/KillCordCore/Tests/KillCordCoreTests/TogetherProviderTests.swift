// Fixtures follow Together's documented schema (it gives no example): https://docs.together.ai/reference/billing-usage
import Foundation
@testable import KillCordCore
import Testing

@Suite struct TogetherProviderTests {
    @Test func addsUpThisMonthsLineItems() async throws {
        let http = MockHTTPClient(routes: ["/v1/billing/usage": try json("together-billing-usage.json")])
        let snapshot = try await TogetherProvider(http: http).fetchSpend(FakeKeys.credentials(.together), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.host == "api.together.ai")
        #expect(request.query("month") == ["2026-11"])
        #expect(request.query("granularity") == ["day"])
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.together)")
        #expect(snapshot.month == usd("1.81"))
        #expect(snapshot.today == nil)
    }

    @Test func followsTheCursor() async throws {
        let first = #"{"data":[{"date":"2026-11-01","line_items":[{"cost":"2.00"}]}],"next_cursor":"c2"}"#
        let second = #"{"data":[{"date":"2026-11-02","line_items":[{"cost":"0.50"}]}],"next_cursor":null}"#
        let http = MockHTTPClient { request in
            HTTPResponse(status: 200, json: request.query("after") == ["c2"] ? second : first)
        }
        let snapshot = try await TogetherProvider(http: http).fetchSpend(FakeKeys.credentials(.together), now: testNow)
        #expect(http.requests.count == 2)
        #expect(snapshot.month == usd("2.50"))
    }

    @Test func notEnabledForTheOrganizationSaysHowToGetIt() async {
        let body = #"{"error":{"message":"Not found","type":"not_found","param":null,"code":null}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 404, json: body) }
        await #expect(throws: SpendError.requiresSetup("ask Together support to turn on the billing usage API. It's "
            + "a beta that Together enables per organization.")) {
            try await TogetherProvider(http: http).fetchSpend(FakeKeys.credentials(.together), now: testNow)
        }
    }

    @Test func aCursorThatNeverEndsStops() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"data":[],"next_cursor":"again"}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await TogetherProvider(http: http).fetchSpend(FakeKeys.credentials(.together), now: testNow)
        }
        #expect(http.requests.count == TogetherProvider.maxPages)
    }
}
