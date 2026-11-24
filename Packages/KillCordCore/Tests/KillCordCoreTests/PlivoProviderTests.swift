// swiftlint:disable line_length
// Fixtures follow Plivo's documented example:
// https://www.plivo.com/docs/account/api/account/retrieve-account-details/
import Foundation
@testable import KillCordCore
import Testing

@Suite struct PlivoProviderTests {
    @Test func readsCashCreditsWithBasicAuth() async throws {
        let http = MockHTTPClient(routes: ["/v1/Account/MAKCTESTAUTHID0115AB": try json("plivo-account.json")])
        let snapshot = try await PlivoProvider(http: http).fetchSpend(FakeKeys.credentials(.plivo), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.plivo.com/v1/Account/MAKCTESTAUTHID0115AB/")
        let basic = Data("MAKCTESTAUTHID0115AB:\(FakeKeys.plivo)".utf8).base64EncodedString()
        #expect(request.headers["Authorization"] == "Basic \(basic)")
        #expect(snapshot.balance == .usd(decimal("1.809")))
    }

    @Test func postpaidAccountsSayTheirCreditsStopNothing() async {
        let body = #"{"cash_credits":"0.00000","auto_recharge":false,"billing_mode":"postpaid"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        do {
            _ = try await PlivoProvider(http: http).fetchSpend(FakeKeys.credentials(.plivo), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            guard case .planNotSupported = error else {
                Issue.record("Unexpected \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func anAuthIDThatWouldChangeThePathIsRefused() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        let credentials = ProviderCredentials(provider: .plivo, values: ["authID": "../Message", "authToken": FakeKeys.plivo])
        await #expect(throws: SpendError.invalidKey) {
            try await PlivoProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func aPostpaidAccountNeverConfirmsTheCreditsCap() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"auto_recharge":false,"billing_mode":"postpaid"}"#) }
        let caps = await PlivoProvider(http: http).verifyCaps(FakeKeys.credentials(.plivo), now: testNow)
        guard case .off = caps.first?.status else {
            Issue.record("Expected off, got \(caps)")
            return
        }
    }

    @Test func anAuthIDWithANewlineIsRefused() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        let credentials = ProviderCredentials(provider: .plivo, values: ["authID": "MA12\nX", "authToken": FakeKeys.plivo])
        await #expect(throws: SpendError.invalidKey) {
            try await PlivoProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func anEchoedTokenIsRedacted() async {
        let body = #"{"error":"Bad token \#(FakeKeys.plivo)"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        do {
            _ = try await PlivoProvider(http: http).fetchSpend(FakeKeys.credentials(.plivo), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(!error.message(for: .plivo).contains(FakeKeys.plivo))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func autoRechargeOffConfirmsTheCap() async throws {
        let http = MockHTTPClient(routes: ["/v1/Account/MAKCTESTAUTHID0115AB": try json("plivo-account.json")])
        let caps = await PlivoProvider(http: http).verifyCaps(FakeKeys.credentials(.plivo), now: testNow)
        #expect(caps.map(\.capID) == [PlivoProvider.autoRechargeCapID])
        guard case .on = caps.first?.status else {
            Issue.record("Expected on, got \(caps)")
            return
        }
    }
}
// swiftlint:enable line_length
