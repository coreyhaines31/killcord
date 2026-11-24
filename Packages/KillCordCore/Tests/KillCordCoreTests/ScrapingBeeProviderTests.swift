// Fixtures follow ScrapingBee's documented response: https://www.scrapingbee.com/documentation/ (Usage endpoint)
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ScrapingBeeProviderTests {
    @Test func readsCreditsLeftOfThePlanWithItsRenewal() async throws {
        let http = MockHTTPClient(routes: ["/api/v1/usage": try json("scrapingbee-usage.json")])
        let snapshot = try await ScrapingBeeProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapingbee),
                                                                             now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://app.scrapingbee.com/api/v1/usage")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.scrapingbee)")
        let renewal = try #require(ISO8601.date("2026-12-03T10:05:58Z"))
        #expect(snapshot.balance == Balance(remaining: 16_295_668, unit: .units("credits"), kind: .allowance,
                                            limit: 20_000_000, used: 3_704_332, resetsAt: renewal))
    }

    @Test func overUsedNeverGoesBelowZero() async throws {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"max_api_credit":1000,"used_api_credit":1200}"#)
        }
        let snapshot = try await ScrapingBeeProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapingbee),
                                                                             now: testNow)
        #expect(snapshot.balance?.remaining == 0)
        #expect(snapshot.balance?.resetsAt == nil)
    }

    @Test func aRejectedKeyIsInvalid() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 401, json: #"{"message":"Invalid api key"}"#) }
        await #expect(throws: SpendError.invalidKey) {
            try await ScrapingBeeProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapingbee), now: testNow)
        }
    }
}
