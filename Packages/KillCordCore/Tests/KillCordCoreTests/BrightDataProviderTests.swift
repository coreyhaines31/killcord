// Fixtures follow Bright Data's documented fields:
// https://docs.brightdata.com/api-reference/account-management-api/Get_total_balance_through_API
import Foundation
@testable import KillCordCore
import Testing

@Suite struct BrightDataProviderTests {
    @Test func readsTheAvailableFundsAndNotPendingCosts() async throws {
        let http = MockHTTPClient(routes: ["/customer/balance": try json("brightdata-customer-balance.json")])
        let snapshot = try await BrightDataProvider(http: http).fetchSpend(FakeKeys.credentials(.brightdata),
                                                                            now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url.absoluteString == "https://api.brightdata.com/customer/balance")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.brightdata)")
        #expect(snapshot.balance == .usd(decimal("220.45")))
        #expect(snapshot.today == nil && snapshot.month == nil)
    }

    @Test func aPlainTextRefusalStillNamesThePermission() async {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 403, headers: ["content-type": "text/plain"], body: Data("Forbidden".utf8))
        }
        await #expect(throws: SpendError.missingScope(hint: "Use a key with the Finance or Admin permission level.")) {
            try await BrightDataProvider(http: http).fetchSpend(FakeKeys.credentials(.brightdata), now: testNow)
        }
    }

    @Test func showsBrightDatasMessageWhenItSendsOne() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: #"{"error":"Customer not found"}"#) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Customer not found")) {
            try await BrightDataProvider(http: http).fetchSpend(FakeKeys.credentials(.brightdata), now: testNow)
        }
    }
}
