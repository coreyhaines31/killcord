// Fixtures follow Exa's documented response: https://exa.ai/docs/reference/team-management/get-team-credits
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ExaProviderTests {
    @Test func readsTheTeamCreditBalanceWithAServiceKey() async throws {
        let http = MockHTTPClient(routes: ["/team-management/credits": try json("exa-team-credits.json")])
        let snapshot = try await ExaProvider(http: http).fetchSpend(FakeKeys.credentials(.exa), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://admin-api.exa.ai/team-management/credits")
        #expect(request.headers["x-api-key"] == FakeKeys.exa)
        #expect(snapshot.balance == .usd(decimal("412.37")))
        #expect(snapshot.today == nil && snapshot.month == nil)
    }

    @Test func noCreditsFieldIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"metadata":{}}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await ExaProvider(http: http).fetchSpend(FakeKeys.credentials(.exa), now: testNow)
        }
    }

    @Test func showsExasOwnErrorMessage() async {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 404, json: #"{"error":"No billing account found for this team."}"#)
        }
        await #expect(throws: SpendError.rejected(status: 404, detail: "No billing account found for this team.")) {
            try await ExaProvider(http: http).fetchSpend(FakeKeys.credentials(.exa), now: testNow)
        }
    }
}
