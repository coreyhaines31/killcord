// Fixtures follow Kie.ai's documented response: https://docs.kie.ai/common-api/get-account-credits
import Foundation
@testable import KillCordCore
import Testing

@Suite struct KieProviderTests {
    @Test func readsCreditsWithTheirEstimatedRate() async throws {
        let http = MockHTTPClient(routes: ["/api/v1/chat/credit": try json("kie-chat-credit.json")])
        let snapshot = try await KieProvider(http: http).fetchSpend(FakeKeys.credentials(.kie), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.kie.ai/api/v1/chat/credit")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.kie)")
        #expect(snapshot.balance == Balance(remaining: decimal("100.5"), unit: .units("credits"), kind: .prepaid,
                                            dollarsPerUnit: decimal("0.005")))
    }

    @Test func aFailureCodeInsideAnOKReplyIsAnError() async {
        let body = #"{"code":401,"msg":"Invalid API key","data":null}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.invalidKey) {
            try await KieProvider(http: http).fetchSpend(FakeKeys.credentials(.kie), now: testNow)
        }
    }

    @Test func showsKiesOwnMessageForOtherFailureCodes() async {
        let body = #"{"code":455,"msg":"Service under maintenance","data":null}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.rejected(status: 455, detail: "Service under maintenance")) {
            try await KieProvider(http: http).fetchSpend(FakeKeys.credentials(.kie), now: testNow)
        }
    }

    @Test func successWithoutCreditsIsAnUnexpectedResponse() async {
        let body = #"{"code":200,"msg":"success","data":null}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await KieProvider(http: http).fetchSpend(FakeKeys.credentials(.kie), now: testNow)
        }
    }
}
