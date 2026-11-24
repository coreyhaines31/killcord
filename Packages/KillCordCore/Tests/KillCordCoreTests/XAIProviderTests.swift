// swiftlint:disable line_length
// Fixtures follow xAI's documented response: https://docs.x.ai/developers/rest-api-reference/management/billing
import Foundation
@testable import KillCordCore
import Testing

@Suite struct XAIProviderTests {
    @Test func readsNegativeCentsAsCreditLeft() async throws {
        let http = MockHTTPClient(routes: ["/v1/billing/teams/65c1e471-205f-4566-9c5a-07198bcdf4ce/prepaid/balance": try json("xai-prepaid-balance.json")])
        let snapshot = try await XAIProvider(http: http).fetchSpend(FakeKeys.credentials(.xai), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://management-api.x.ai/v1/billing/teams/65c1e471-205f-4566-9c5a-07198bcdf4ce/prepaid/balance")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.xai)")
        #expect(snapshot.balance == .usd(Decimal(string: "17.35")!))
    }

    @Test func spendPastTheCreditShowsAsNegative() {
        #expect(XAIProvider.credit(cents: 250) == Decimal(string: "-2.5"))
        #expect(XAIProvider.credit(cents: 0) == 0)
    }

    @Test func aTeamIDThatCouldChangeThePathIsRefused() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"total":{"val":"-1"}}"#) }
        for team in ["../../v1/auth", "abc/def", "a b", "team?x=1"] {
            let credentials = ProviderCredentials(provider: .xai, values: ["managementKey": FakeKeys.xai, "teamID": team])
            await #expect(throws: SpendError.self) {
                try await XAIProvider(http: http).fetchSpend(credentials, now: testNow)
            }
        }
        #expect(http.requests.isEmpty)
    }

    @Test func aMissingTotalIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"changes":[]}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await XAIProvider(http: http).fetchSpend(FakeKeys.credentials(.xai), now: testNow)
        }
    }

    @Test func showsXAIsMessageWhenItSendsOne() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 404, json: #"{"code":"NOT_FOUND","message":"Team not found"}"#) }
        await #expect(throws: SpendError.rejected(status: 404, detail: "Team not found")) {
            try await XAIProvider(http: http).fetchSpend(FakeKeys.credentials(.xai), now: testNow)
        }
    }
}
// swiftlint:enable line_length
