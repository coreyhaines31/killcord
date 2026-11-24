// Fixtures follow Runpod's documented response and errors:
// https://docs.runpod.io/api-reference-v2/billing/get-the-account-balance
import Foundation
@testable import KillCordCore
import Testing

@Suite struct RunpodProviderTests {
    @Test func readsThePrepaidBalanceWithABearerKey() async throws {
        let http = MockHTTPClient(routes: ["/v2/billing/balance": try json("runpod-billing-balance.json")])
        let snapshot = try await RunpodProvider(http: http).fetchSpend(FakeKeys.credentials(.runpod), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.runpod.io/v2/billing/balance")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.runpod)")
        #expect(snapshot.balance == .usd(decimal("42.18")))
        #expect(snapshot.today == nil && snapshot.month == nil)
    }

    @Test func aPostpaidAccountSaysItsBalanceStopsNothing() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"balanceAmount":0,"billingMode":"POSTPAID"}"#) }
        do {
            _ = try await RunpodProvider(http: http).fetchSpend(FakeKeys.credentials(.runpod), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            guard case .planNotSupported(let text) = error else {
                Issue.record("Unexpected \(error)")
                return
            }
            #expect(text.contains("prepaid"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func anUnknownBillingModeIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"balanceAmount":5,"billingMode":"OTHER"}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await RunpodProvider(http: http).fetchSpend(FakeKeys.credentials(.runpod), now: testNow)
        }
    }

    @Test func aKeyWithoutBillingReadNamesTheScope() async {
        let body = #"{"title":"Forbidden","status":403,"detail":"access denied"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: body) }
        do {
            _ = try await RunpodProvider(http: http).fetchSpend(FakeKeys.credentials(.runpod), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error.message(for: .runpod).contains("billing:read"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func showsRunpodsProblemDetail() async {
        let body = #"{"title":"Not Found","status":404,"detail":"resource not found"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 404, json: body) }
        await #expect(throws: SpendError.rejected(status: 404, detail: "resource not found")) {
            try await RunpodProvider(http: http).fetchSpend(FakeKeys.credentials(.runpod), now: testNow)
        }
    }
}
