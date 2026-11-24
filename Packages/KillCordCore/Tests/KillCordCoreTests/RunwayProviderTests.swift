// Fixtures follow Runway's documented schema for GET /v1/organization: https://docs.dev.runwayml.com/api
// Credit price: https://docs.dev.runwayml.com/guides/pricing
import Foundation
@testable import KillCordCore
import Testing

@Suite struct RunwayProviderTests {
    @Test func readsCreditsWithTheVersionHeader() async throws {
        let http = MockHTTPClient(routes: ["/v1/organization": try json("runway-organization.json")])
        let snapshot = try await RunwayProvider(http: http).fetchSpend(FakeKeys.credentials(.runway), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url.absoluteString == "https://api.dev.runwayml.com/v1/organization")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.runway)")
        #expect(request.headers["X-Runway-Version"] == "2024-11-06")
        let balance = try #require(snapshot.balance)
        #expect(balance.remaining == 4250)
        #expect(balance.unit == .units("credits"))
        #expect(balance.kind == .prepaid)
        // The tier's monthly maximum limits purchases, not use, so it isn't a limit here.
        #expect(balance.limit == nil)
        #expect(balance.estimatedDollars == Money(decimal("42.5")))
        #expect(BalanceText.details(balance).contains("About $42.50 at $0.01 a credit (estimate)."))
    }

    @Test func showsRunwaysOwnErrorString() async {
        let body = #"{"error":"Invalid API version","docUrl":"https://docs.dev.runwayml.com/api"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Invalid API version")) {
            try await RunwayProvider(http: http).fetchSpend(FakeKeys.credentials(.runway), now: testNow)
        }
    }

    @Test func noCreditBalanceIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"tier":{},"usage":{}}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await RunwayProvider(http: http).fetchSpend(FakeKeys.credentials(.runway), now: testNow)
        }
    }
}
