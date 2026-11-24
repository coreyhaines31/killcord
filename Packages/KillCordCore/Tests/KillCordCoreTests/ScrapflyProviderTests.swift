// Fixtures follow Scrapfly's documented response (with its `#` comment removed): https://scrapfly.io/docs/account
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ScrapflyProviderTests {
    @Test func readsScrapeCreditsLeftWithTheKeyInTheQuery() async throws {
        let http = MockHTTPClient(routes: ["/account": try json("scrapfly-account.json")])
        let snapshot = try await ScrapflyProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapfly), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.scrapfly.io/account?key=\(FakeKeys.scrapfly)")
        let periodEnd = try #require(ISO8601.date("2026-12-03T00:00:00Z"))
        #expect(snapshot.balance == Balance(remaining: 684_996, unit: .units("credits"), kind: .allowance,
                                            limit: 1_000_000, used: 315_004, resetsAt: periodEnd))
    }

    @Test func anErrorNeverShowsTheKeyFromTheAddress() async {
        let body = #"{"message":"Invalid API key \#(FakeKeys.scrapfly)","code":"ERR::SCRAPE::BAD_API_KEY"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Invalid API key [redacted]")) {
            try await ScrapflyProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapfly), now: testNow)
        }
    }

    @Test func noScrapeUsageIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"subscription":{"usage":{}}}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await ScrapflyProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapfly), now: testNow)
        }
    }
}
