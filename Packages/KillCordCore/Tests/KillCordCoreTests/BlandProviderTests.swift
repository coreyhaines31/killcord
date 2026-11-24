// Fixtures follow Bland's documented response: https://docs.bland.ai/api-v1/get/me
import Foundation
@testable import KillCordCore
import Testing

@Suite struct BlandProviderTests {
    @Test func readsCreditsWithABareKeyHeader() async throws {
        let http = MockHTTPClient(routes: ["/v1/me": try json("bland-me.json")])
        let snapshot = try await BlandProvider(http: http).fetchSpend(FakeKeys.credentials(.bland), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.bland.ai/v1/me")
        #expect(request.headers["authorization"] == FakeKeys.bland)
        #expect(snapshot.balance == Balance(remaining: decimal("42.1210000034"), unit: .units("credits"), kind: .prepaid))
        #expect(snapshot.balance?.estimatedDollars == nil)
    }

    @Test func showsBlandsOwnErrorMessage() async {
        let body = #"{"status":"error","data":null,"errors":[{"error":"BAD_REQUEST","message":"Organization is paused"}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Organization is paused")) {
            try await BlandProvider(http: http).fetchSpend(FakeKeys.credentials(.bland), now: testNow)
        }
    }

    @Test func noBillingObjectIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"status":"active","total_calls":3}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await BlandProvider(http: http).fetchSpend(FakeKeys.credentials(.bland), now: testNow)
        }
    }
}
