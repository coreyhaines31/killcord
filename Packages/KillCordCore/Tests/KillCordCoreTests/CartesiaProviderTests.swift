// Fixtures follow Cartesia's documented response: https://docs.cartesia.ai/api-reference/usage/credits
import Foundation
@testable import KillCordCore
import Testing

@Suite struct CartesiaProviderTests {
    @Test func readsCreditsUsedThisMonthWithTheVersionHeader() async throws {
        let http = MockHTTPClient(routes: ["/usage/credits": try json("cartesia-usage-credits.json")])
        let snapshot = try await CartesiaProvider(http: http).fetchSpend(FakeKeys.credentials(.cartesia), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.host == "api.cartesia.ai")
        #expect(request.query("start_ts") == ["2026-11-01T00:00:00Z"])
        #expect(request.query("end_ts") == ["2026-11-15T18:30:00Z"])
        #expect(request.query("interval").isEmpty)
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.cartesia)")
        #expect(request.headers["Cartesia-Version"] == "2026-08-14")
        #expect(snapshot.usage == [UsageMetric(id: "credits", name: "Credits used", value: 21_980, unit: "credits")])
        #expect(snapshot.today == nil && snapshot.month == nil && snapshot.balance == nil)
    }

    @Test func noBucketsIsZeroUsed() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"data":[]}"#) }
        let snapshot = try await CartesiaProvider(http: http).fetchSpend(FakeKeys.credentials(.cartesia), now: testNow)
        #expect(snapshot.usage.first?.value == 0)
    }

    @Test func showsCartesiasOwnMessage() async {
        let body = #"{"error_code":"invalid_request","title":"Invalid request","message":"start_ts is invalid","#
            + #""request_id":"r1"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "start_ts is invalid")) {
            try await CartesiaProvider(http: http).fetchSpend(FakeKeys.credentials(.cartesia), now: testNow)
        }
    }
}
