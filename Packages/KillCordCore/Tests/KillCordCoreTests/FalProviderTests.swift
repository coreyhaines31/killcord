// swiftlint:disable line_length
// Fixtures follow fal's documented response: https://fal.ai/docs/platform-apis/v1/account/billing
import Foundation
@testable import KillCordCore
import Testing

@Suite struct FalProviderTests {
    @Test func readsTheCreditBalanceWithAKeyHeader() async throws {
        let http = MockHTTPClient(routes: ["/v1/account/billing": try json("fal-account-billing.json")])
        let snapshot = try await FalProvider(http: http).fetchSpend(FakeKeys.credentials(.fal), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.fal.ai/v1/account/billing?expand=credits")
        #expect(request.headers["Authorization"] == "Key \(FakeKeys.fal)")
        #expect(snapshot.balance == .usd(Decimal(string: "24.5")!))
        #expect(snapshot.today == nil && snapshot.month == nil)
    }

    @Test func noCreditsObjectIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"username":"kc-test-team"}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await FalProvider(http: http).fetchSpend(FakeKeys.credentials(.fal), now: testNow)
        }
    }

    @Test func showsFalsOwnErrorMessage() async {
        let body = #"{"error":{"type":"validation_error","message":"Invalid expand value"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Invalid expand value")) {
            try await FalProvider(http: http).fetchSpend(FakeKeys.credentials(.fal), now: testNow)
        }
    }

    @Test func aKeyWithoutBillingReadNamesThePreset() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: #"{"error":{"type":"authorization_error","message":"Access denied"}}"#) }
        do {
            _ = try await FalProvider(http: http).fetchSpend(FakeKeys.credentials(.fal), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error.message(for: .fal).contains("BILLING preset"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }
}
// swiftlint:enable line_length
