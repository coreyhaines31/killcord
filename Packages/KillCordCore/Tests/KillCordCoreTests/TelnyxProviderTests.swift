// swiftlint:disable line_length
// Fixtures follow Telnyx's documented examples:
// https://developers.telnyx.com/api-reference/billing/get-user-balance-details and
// https://developers.telnyx.com/api-reference/autorechargepreferences/list-auto-recharge-preferences
import Foundation
@testable import KillCordCore
import Testing

@Suite struct TelnyxProviderTests {
    @Test func readsAvailableCreditInItsCurrency() async throws {
        let http = MockHTTPClient(routes: ["/v2/balance": try json("telnyx-balance.json")])
        let snapshot = try await TelnyxProvider(http: http).fetchSpend(FakeKeys.credentials(.telnyx), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.telnyx.com/v2/balance")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.telnyx)")
        #expect(snapshot.balance == .usd(decimal("400.00")))
    }

    @Test func keepsANonDollarCurrency() async throws {
        let body = #"{"data":{"balance":"50.00","credit_limit":"0.00","available_credit":"50.00","currency":"EUR"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await TelnyxProvider(http: http).fetchSpend(FakeKeys.credentials(.telnyx), now: testNow)
        #expect(snapshot.balance == Balance(remaining: decimal("50.00"), unit: .money(Currency("EUR"))))
    }

    @Test func showsTelnyxsErrorDetail() async {
        let body = #"{"errors":[{"code":"10027","title":"Unprocessable Entity","detail":"Invalid or missing account information"}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 422, json: body) }
        await #expect(throws: SpendError.rejected(status: 422, detail: "Invalid or missing account information")) {
            try await TelnyxProvider(http: http).fetchSpend(FakeKeys.credentials(.telnyx), now: testNow)
        }
    }

    @Test func autoRechargeOffConfirmsTheCap() async {
        let body = #"{"data":{"id":"1","record_type":"auto_recharge_pref","enabled":false,"threshold_amount":"0.00","recharge_amount":"0.00"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let caps = await TelnyxProvider(http: http).verifyCaps(FakeKeys.credentials(.telnyx), now: testNow)
        #expect(http.requests.first?.url.absoluteString == "https://api.telnyx.com/v2/payment/auto_recharge_prefs")
        #expect(caps.count == 1)
        guard case .on = caps.first?.status else {
            Issue.record("Expected on, got \(caps)")
            return
        }
    }

    @Test func autoRechargeOnMeansTheBalanceDoesNotStop() async {
        let body = #"{"data":{"enabled":true,"threshold_amount":"104.00","recharge_amount":"104.00","preference":"credit_paypal"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let caps = await TelnyxProvider(http: http).verifyCaps(FakeKeys.credentials(.telnyx), now: testNow)
        guard case .off(let detail) = caps.first?.status else {
            Issue.record("Expected off, got \(caps)")
            return
        }
        #expect(detail.contains("104"))
        #expect(caps.first?.capID == TelnyxProvider.autoRechargeCapID)
    }
}
// swiftlint:enable line_length
