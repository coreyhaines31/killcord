// Fixtures follow Stability AI's documented response: https://docs.stability.ai/api-reference/user/account-balance
import Foundation
@testable import KillCordCore
import Testing

@Suite struct StabilityProviderTests {
    @Test func readsCreditsWithTheirDollarRate() async throws {
        let http = MockHTTPClient(routes: ["/v1/user/balance": try json("stability-user-balance.json")])
        let snapshot = try await StabilityProvider(http: http).fetchSpend(FakeKeys.credentials(.stability), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.stability.ai/v1/user/balance")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.stability)")
        let balance = try #require(snapshot.balance)
        #expect(balance == Balance(remaining: decimal("1234.5"), unit: .units("credits"), kind: .prepaid,
                                   dollarsPerUnit: decimal("0.01")))
        #expect(balance.estimatedDollars == usd("12.345"))
        #expect(snapshot.today == nil && snapshot.month == nil)
    }

    @Test func noCreditsFieldIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"balance":3}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await StabilityProvider(http: http).fetchSpend(FakeKeys.credentials(.stability), now: testNow)
        }
    }

    @Test func showsStabilitysOwnErrorMessage() async {
        let body = #"{"id":"9160aa70222c4e3a9d1e4c6b2ea8e1e0","name":"bad_request","message":"Organization not found"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Organization not found")) {
            try await StabilityProvider(http: http).fetchSpend(FakeKeys.credentials(.stability), now: testNow)
        }
    }
}
