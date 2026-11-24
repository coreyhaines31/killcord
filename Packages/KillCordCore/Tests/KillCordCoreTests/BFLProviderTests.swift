// Fixtures follow Black Forest Labs' documented response: https://docs.bfl.ai/api-reference/get-the-users-credits
import Foundation
@testable import KillCordCore
import Testing

@Suite struct BFLProviderTests {
    @Test func readsCreditsWithTheXKeyHeader() async throws {
        let http = MockHTTPClient(routes: ["/v1/credits": try json("bfl-credits.json")])
        let snapshot = try await BFLProvider(http: http).fetchSpend(FakeKeys.credentials(.bfl), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.bfl.ai/v1/credits")
        #expect(request.headers["x-key"] == FakeKeys.bfl)
        #expect(request.headers["Authorization"] == nil)
        let balance = try #require(snapshot.balance)
        #expect(balance.remaining == decimal("1234.5"))
        #expect(balance.unit == .units("credits"))
        // "1 credit = $0.01 USD", shown as a labeled estimate.
        #expect(balance.estimatedDollars == usd("12.345"))
        #expect(snapshot.today == nil && snapshot.month == nil)
    }

    @Test func noCreditsFieldIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"balance":5}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await BFLProvider(http: http).fetchSpend(FakeKeys.credentials(.bfl), now: testNow)
        }
    }

    @Test func aRejectedKeyIsInvalid() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 401, json: #"{"detail":"Not authenticated"}"#) }
        await #expect(throws: SpendError.invalidKey) {
            try await BFLProvider(http: http).fetchSpend(FakeKeys.credentials(.bfl), now: testNow)
        }
    }
}
