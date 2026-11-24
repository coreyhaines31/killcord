// swiftlint:disable line_length
// Fixtures follow the X API's documented schema: https://docs.x.com/x-api/usage/get-usage-credits
import Foundation
@testable import KillCordCore
import Testing

@Suite struct XAPIProviderTests {
    @Test func readsTheSpendableCreditBalance() async throws {
        let http = MockHTTPClient(routes: ["/2/usage/credits": try json("xapi-usage-credits.json")])
        let snapshot = try await XAPIProvider(http: http).fetchSpend(FakeKeys.credentials(.xapi), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.x.com/2/usage/credits")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.xapi)")
        #expect(snapshot.balance == .usd(decimal("12.5")))
        #expect(snapshot.today == nil && snapshot.month == nil)
    }

    @Test func anOverdrawnPrepaidBucketShowsTheClampedTotal() async throws {
        let body = #"{"data":{"total_balance":0,"prepaid_balance":-1.25,"free_balance":0,"free_grants":[]}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await XAPIProvider(http: http).fetchSpend(FakeKeys.credentials(.xapi), now: testNow)
        #expect(snapshot.balance == .usd(0))
    }

    @Test func noDataIsAnUnexpectedResponse() async {
        let body = #"{"errors":[{"title":"Not Found Error","detail":"Could not find credits.","type":"https://api.x.com/2/problems/resource-not-found"}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await XAPIProvider(http: http).fetchSpend(FakeKeys.credentials(.xapi), now: testNow)
        }
    }

    @Test func showsTheProblemDetail() async {
        let body = #"{"title":"Invalid Request","detail":"One or more parameters to your request was invalid.","type":"https://api.x.com/2/problems/invalid-request"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400,
                                                  detail: "One or more parameters to your request was invalid.")) {
            try await XAPIProvider(http: http).fetchSpend(FakeKeys.credentials(.xapi), now: testNow)
        }
    }
}
// swiftlint:enable line_length
