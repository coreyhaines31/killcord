// swiftlint:disable line_length
// Fixtures follow the documented examples: https://prospeo.io/api-docs/account-information and
// https://developer.lemlist.com/api-reference/endpoints/team/get-team-credits
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ProspeoProviderTests {
    @Test func readsRemainingCreditsAndTheRenewalDate() async throws {
        let http = MockHTTPClient(routes: ["/account-information": try json("prospeo-account-information.json")])
        let snapshot = try await ProspeoProvider(http: http).fetchSpend(FakeKeys.credentials(.prospeo), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.prospeo.io/account-information")
        #expect(request.headers["X-KEY"] == FakeKeys.prospeo)
        #expect(snapshot.balance == Balance(remaining: 99, unit: .units("credits"), kind: .allowance, used: 1,
                                            resetsAt: ISO8601.date("2026-12-10T20:52:28Z")))
    }

    @Test func invalidAPIKeyIsARejectedKey() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: #"{"error":true,"error_code":"INVALID_API_KEY"}"#) }
        await #expect(throws: SpendError.invalidKey) {
            try await ProspeoProvider(http: http).fetchSpend(FakeKeys.credentials(.prospeo), now: testNow)
        }
    }

    @Test func otherErrorsShowTheirCode() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: #"{"error":true,"error_code":"INVALID_REQUEST"}"#) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "INVALID_REQUEST")) {
            try await ProspeoProvider(http: http).fetchSpend(FakeKeys.credentials(.prospeo), now: testNow)
        }
    }

    @Test func aReplyWithoutResponseIsUnexpected() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"error":false}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await ProspeoProvider(http: http).fetchSpend(FakeKeys.credentials(.prospeo), now: testNow)
        }
    }
}

@Suite struct LemlistProviderTests {
    @Test func readsTeamCreditsWithAnEmptyBasicLogin() async throws {
        let http = MockHTTPClient(routes: ["/api/team/credits": try json("lemlist-team-credits.json")])
        let snapshot = try await LemlistProvider(http: http).fetchSpend(FakeKeys.credentials(.lemlist), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.lemlist.com/api/team/credits")
        #expect(request.headers["Authorization"] == "Basic " + Data(":\(FakeKeys.lemlist)".utf8).base64EncodedString())
        #expect(snapshot.balance == Balance(remaining: 100, unit: .units("credits")))
    }

    @Test func aPlainTextRejectionIsAnInvalidKey() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 401, headers: ["content-type": "text/plain"], body: Data("The authentication you supplied is incorrect".utf8)) }
        await #expect(throws: SpendError.invalidKey) {
            try await LemlistProvider(http: http).fetchSpend(FakeKeys.credentials(.lemlist), now: testNow)
        }
    }
}
// swiftlint:enable line_length
