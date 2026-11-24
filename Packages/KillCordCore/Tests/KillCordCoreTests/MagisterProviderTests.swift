// Fixtures follow Magister's documented fields: https://magistermarketing.com/docs/api (GET /v1/credits)
import Foundation
@testable import KillCordCore
import Testing

@Suite struct MagisterProviderTests {
    @Test func readsAvailableCreditsWithTheirPrice() async throws {
        let body = #"{"data":{"balance":1200,"held":75,"available":1125,"price_per_credit_usd":0.02},"#
            + #""credits_charged":0,"request_id":"req_1"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await MagisterProvider(http: http).fetchSpend(FakeKeys.credentials(.magister), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.magistermarketing.com/v1/credits")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.magister)")
        #expect(snapshot.balance == Balance(remaining: 1125, unit: .units("credits"), kind: .prepaid,
                                            dollarsPerUnit: decimal("0.02")))
    }

    @Test func noDataIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"credits_charged":0}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await MagisterProvider(http: http).fetchSpend(FakeKeys.credentials(.magister), now: testNow)
        }
    }

    @Test func showsMagistersOwnMessage() async {
        let body = #"{"error":"not_enabled","message":"The API is not enabled for this organization.","retryable":false}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 404, json: body) }
        await #expect(throws: SpendError.rejected(status: 404, detail: "The API is not enabled for this organization.")) {
            try await MagisterProvider(http: http).fetchSpend(FakeKeys.credentials(.magister), now: testNow)
        }
    }
}
