// swiftlint:disable line_length
// Fixtures follow Tavily's documented response fields: https://docs.tavily.com/documentation/api-reference/endpoint/usage
import Foundation
@testable import KillCordCore
import Testing

@Suite struct TavilyProviderTests {
    @Test func readsThePlansCreditsLeft() async throws {
        let http = MockHTTPClient(routes: ["/usage": try json("tavily-usage.json")])
        let snapshot = try await TavilyProvider(http: http).fetchSpend(FakeKeys.credentials(.tavily), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url.absoluteString == "https://api.tavily.com/usage")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.tavily)")
        // Pay-as-you-go credits are counted apart and not added in.
        #expect(snapshot.balance == Balance(remaining: 10_800, unit: .units("credits"), kind: .allowance, limit: 15_000, used: 4_200))
    }

    @Test func aPayAsYouGoOnlyAccountShowsNoPlanBalance() async throws {
        let body = #"{"key":{"usage":5,"limit":null},"account":{"current_plan":"Researcher","plan_usage":0,"plan_limit":0,"paygo_usage":5,"paygo_limit":500}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await TavilyProvider(http: http).fetchSpend(FakeKeys.credentials(.tavily), now: testNow)
        #expect(snapshot.balance == nil)
    }

    @Test func checksNoMoreOftenThanTheUsageRateLimitAllows() {
        // 10 requests per 10 minutes, shared with whatever else reads usage.
        #expect(ProviderID.tavily.info.minimumRefreshInterval >= 60)
    }

    @Test func showsTavilysOwnMessage() async {
        let body = #"{"detail":{"error":"Your request has been blocked due to excessive requests. Please reduce the rate of requests."}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 432, json: body) }
        await #expect(throws: SpendError.rejected(status: 432, detail: "Your request has been blocked due to excessive requests. Please reduce the rate of requests.")) {
            try await TavilyProvider(http: http).fetchSpend(FakeKeys.credentials(.tavily), now: testNow)
        }
    }
}
// swiftlint:enable line_length
