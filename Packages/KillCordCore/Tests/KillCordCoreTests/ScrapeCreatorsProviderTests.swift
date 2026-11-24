// Fixtures follow ScrapeCreators' documented response (OpenAPI example for /v1/account/credit-balance):
// https://docs.scrapecreators.com/v1/credit-balance
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ScrapeCreatorsProviderTests {
    @Test func readsPrepaidCredits() async throws {
        let http = MockHTTPClient(routes: ["/v1/account/credit-balance": try json("scrapecreators-credit-balance.json")])
        let snapshot = try await ScrapeCreatorsProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapecreators),
                                                                                now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.scrapecreators.com/v1/account/credit-balance")
        #expect(request.headers["x-api-key"] == FakeKeys.scrapecreators)
        #expect(snapshot.balance == Balance(remaining: 333, unit: .units("credits"), kind: .prepaid))
    }

    @Test func aFailedReplyIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"success":false,"creditCount":0}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await ScrapeCreatorsProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapecreators), now: testNow)
        }
    }

    @Test func showsScrapeCreatorsMessageWhenItSendsOne() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: #"{"success":false,"message":"Invalid API key"}"#) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Invalid API key")) {
            try await ScrapeCreatorsProvider(http: http).fetchSpend(FakeKeys.credentials(.scrapecreators), now: testNow)
        }
    }
}
