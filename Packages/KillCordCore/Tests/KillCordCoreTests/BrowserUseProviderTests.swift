// Fixtures follow Browser Use's documented schema:
// https://docs.browser-use.com/cloud/api-v2/billing/get-account-billing
import Foundation
@testable import KillCordCore
import Testing

@Suite struct BrowserUseProviderTests {
    @Test func readsTheProjectsTotalCredits() async throws {
        let http = MockHTTPClient(routes: ["/api/v2/billing/account": try json("browseruse-billing-account.json")])
        let snapshot = try await BrowserUseProvider(http: http).fetchSpend(FakeKeys.credentials(.browseruse),
                                                                          now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.browser-use.com/api/v2/billing/account")
        #expect(request.headers["X-Browser-Use-API-Key"] == FakeKeys.browseruse)
        #expect(request.headers["Authorization"] == nil)
        #expect(snapshot.balance == .usd(decimal("42.5")))
    }

    @Test func anUnknownProjectShowsBrowserUsesDetail() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 404, json: #"{"detail":"Account not found"}"#) }
        await #expect(throws: SpendError.rejected(status: 404, detail: "Account not found")) {
            try await BrowserUseProvider(http: http).fetchSpend(FakeKeys.credentials(.browseruse), now: testNow)
        }
    }
}
