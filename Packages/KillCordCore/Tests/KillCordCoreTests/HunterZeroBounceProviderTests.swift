// swiftlint:disable line_length
// Fixtures follow the documented examples: https://hunter.io/api-documentation/v2#account and
// https://www.zerobounce.net/docs/email-validation-api-quickstart/v2-credit-balance
import Foundation
@testable import KillCordCore
import Testing

@Suite struct HunterProviderTests {
    @Test func readsTheCreditsPoolWithItsResetDate() async throws {
        let http = MockHTTPClient(routes: ["/v2/account": try json("hunter-account.json")])
        let snapshot = try await HunterProvider(http: http).fetchSpend(FakeKeys.credentials(.hunter), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.hunter.io/v2/account")
        #expect(request.headers["X-API-KEY"] == FakeKeys.hunter)
        let balance = try #require(snapshot.balance)
        #expect(balance == Balance(remaining: 9450, unit: .units("credits"), kind: .allowance, limit: 10000, used: 550,
                                   resetsAt: ISO8601.date("2026-12-02T00:00:00Z")))
    }

    @Test func separateQuotasShowSearchesLeft() async throws {
        let body = #"{"data":{"reset_date":"2026-12-02","requests":{"searches":{"used":20,"available":50,"remaining":30},"verifications":{"used":0,"available":100,"remaining":100}}}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let balance = try #require(try await HunterProvider(http: http).fetchSpend(FakeKeys.credentials(.hunter), now: testNow).balance)
        #expect(balance.remaining == 30 && balance.unit == .units("searches"))
    }

    @Test func a403IsHuntersRateLimit() async {
        let body = #"{"errors":[{"id":"too_many_requests","code":403,"details":"You have reached the rate limit."}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: body) }
        await #expect(throws: SpendError.rateLimited(retryAfter: nil)) {
            try await HunterProvider(http: http).fetchSpend(FakeKeys.credentials(.hunter), now: testNow)
        }
    }

    @Test func showsHuntersErrorDetails() async {
        let body = #"{"errors":[{"id":"wrong_params","code":400,"details":"You are missing the api_key parameter"}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "You are missing the api_key parameter")) {
            try await HunterProvider(http: http).fetchSpend(FakeKeys.credentials(.hunter), now: testNow)
        }
    }
}

@Suite struct ZeroBounceProviderTests {
    @Test func readsCreditsWithTheKeyInTheQuery() async throws {
        let http = MockHTTPClient(routes: ["/v2/getcredits": try json("zerobounce-getcredits.json")])
        let snapshot = try await ZeroBounceProvider(http: http).fetchSpend(FakeKeys.credentials(.zerobounce), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.zerobounce.net/v2/getcredits?api_key=\(FakeKeys.zerobounce)")
        #expect(snapshot.balance == Balance(remaining: 2_375_323, unit: .units("credits")))
    }

    @Test func minusOneMeansTheKeyIsInvalid() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"Credits":"-1"}"#) }
        await #expect(throws: SpendError.invalidKey) {
            try await ZeroBounceProvider(http: http).fetchSpend(FakeKeys.credentials(.zerobounce), now: testNow)
        }
    }

    @Test func anEchoedKeyIsRedacted() async {
        let body = #"{"error":"Invalid API key \#(FakeKeys.zerobounce)"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        do {
            _ = try await ZeroBounceProvider(http: http).fetchSpend(FakeKeys.credentials(.zerobounce), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(!error.message(for: .zerobounce).contains(FakeKeys.zerobounce))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }
}
// swiftlint:enable line_length
