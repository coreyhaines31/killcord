// Fixtures follow SearchApi's documented example: https://www.searchapi.io/docs/account-api
import Foundation
@testable import KillCordCore
import Testing

@Suite struct SearchApiProviderTests {
    @Test func readsSearchesLeftWithABearerKey() async throws {
        let http = MockHTTPClient(routes: ["/api/v1/me": try json("searchapi-me.json")])
        let snapshot = try await SearchApiProvider(http: http).fetchSpend(FakeKeys.credentials(.searchapi), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://www.searchapi.io/api/v1/me")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.searchapi)")
        #expect(snapshot.balance == Balance(remaining: 5200, unit: .units("searches"), kind: .allowance, limit: 10000,
                                            used: 4800, resetsAt: ISO8601.date("2026-12-04T00:34:59Z")))
    }

    @Test func earlyRenewalOnMeansSearchesDoNotStop() async throws {
        let http = MockHTTPClient(routes: ["/api/v1/me": try json("searchapi-me.json")])
        let caps = await SearchApiProvider(http: http).verifyCaps(FakeKeys.credentials(.searchapi), now: testNow)
        #expect(caps.map(\.capID) == [SearchApiProvider.earlyRenewalCapID])
        guard case .off = caps.first?.status else {
            Issue.record("Expected off, got \(caps)")
            return
        }
    }

    @Test func anAbsentEarlyRenewalFlagMeansItIsOff() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"account":{"remaining_searches":12}}"#) }
        let caps = await SearchApiProvider(http: http).verifyCaps(FakeKeys.credentials(.searchapi), now: testNow)
        guard case .on = caps.first?.status else {
            Issue.record("Expected on, got \(caps)")
            return
        }
    }

    @Test func noAccountIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"api_usage":{}}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await SearchApiProvider(http: http).fetchSpend(FakeKeys.credentials(.searchapi), now: testNow)
        }
    }
}
