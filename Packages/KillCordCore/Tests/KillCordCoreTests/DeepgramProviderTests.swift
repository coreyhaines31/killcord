// swiftlint:disable line_length
// Fixtures follow Deepgram's documented responses: https://developers.deepgram.com/reference/manage/billing/list
// and https://developers.deepgram.com/reference/manage/projects/list
import Foundation
@testable import KillCordCore
import Testing

@Suite struct DeepgramProviderTests {
    static let project = "3a6f8c1e-TEST-4b2d-9c51-0a7e2f3b4c5d"

    func client() throws -> MockHTTPClient {
        MockHTTPClient(routes: ["/v1/projects": try json("deepgram-projects.json"),
                                "/v1/projects/\(Self.project)/balances": try json("deepgram-balances.json")])
    }

    @Test func findsTheOnlyProjectThenAddsUpItsDollarBalances() async throws {
        let http = try client()
        let snapshot = try await DeepgramProvider(http: http).fetchSpend(FakeKeys.credentials(.deepgram), now: testNow)
        #expect(http.requests.map(\.url.absoluteString) == ["https://api.deepgram.com/v1/projects",
                                                            "https://api.deepgram.com/v1/projects/\(Self.project)/balances"])
        #expect(http.requests.allSatisfy { $0.method == .get && $0.headers["Authorization"] == "Token \(FakeKeys.deepgram)" })
        #expect(snapshot.balance == .usd(decimal("162.37")))
    }

    @Test func aSavedProjectIDSkipsTheLookup() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .deepgram, values: ["apiKey": FakeKeys.deepgram, "projectID": Self.project])
        _ = try await DeepgramProvider(http: http).fetchSpend(credentials, now: testNow)
        #expect(http.requests.map(\.url.path) == ["/v1/projects/\(Self.project)/balances"])
    }

    @Test func severalProjectsNeedAnID() async {
        let body = #"{"projects":[{"project_id":"p-1","name":"A"},{"project_id":"p-2","name":"B"}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.requiresSetup("this key can see 2 projects. Add the project ID to choose one.")) {
            try await DeepgramProvider(http: http).fetchSpend(FakeKeys.credentials(.deepgram), now: testNow)
        }
    }

    @Test func aProjectIDThatCouldChangeThePathIsRefused() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"balances":[]}"#) }
        let credentials = ProviderCredentials(provider: .deepgram, values: ["apiKey": FakeKeys.deepgram, "projectID": "../keys"])
        await #expect(throws: SpendError.self) {
            try await DeepgramProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func noOutstandingBalanceIsZeroAndOtherUnitsKeepTheirName() throws {
        #expect(try DeepgramProvider.balance([]) == .usd(0))
        let hours = [DeepgramProvider.Balances.Entry(amount: nil, units: "hour")]
        #expect(try DeepgramProvider.balance(hours) == Balance(remaining: 0, unit: .units("hour")))
        let mixed = [DeepgramProvider.Balances.Entry(amount: nil, units: "hour"), .init(amount: nil, units: "token")]
        #expect(throws: SpendError.unexpectedResponse) { try DeepgramProvider.balance(mixed) }
    }

    @Test func aMemberKeyIsToldWhichRoleItNeeds() async {
        let body = #"{"category":"INSUFFICIENT_PERMISSIONS","message":"Project not found or you do not have permission","details":"","request_id":"r1"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: body) }
        await #expect(throws: SpendError.missingScope(hint: "Use a key with the Admin or Owner role: Deepgram gives billing:read to those roles only.")) {
            try await DeepgramProvider(http: http).fetchSpend(FakeKeys.credentials(.deepgram), now: testNow)
        }
    }

    @Test func showsDeepgramsOldErrorShape() async {
        let body = #"{"err_code":"INVALID_QUERY_PARAMETER","err_msg":"Project ID is invalid.","request_id":"r2"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Project ID is invalid.")) {
            try await DeepgramProvider(http: http).fetchSpend(FakeKeys.credentials(.deepgram), now: testNow)
        }
    }
}
// swiftlint:enable line_length
