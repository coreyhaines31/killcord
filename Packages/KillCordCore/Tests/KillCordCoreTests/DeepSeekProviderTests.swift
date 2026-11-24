// swiftlint:disable line_length
// Fixtures follow DeepSeek's documented response: https://api-docs.deepseek.com/api/get-user-balance
import Foundation
@testable import KillCordCore
import Testing

@Suite struct DeepSeekProviderTests {
    @Test func readsTheBalanceFromAString() async throws {
        let http = MockHTTPClient(routes: ["/user/balance": try json("deepseek-user-balance.json")])
        let snapshot = try await DeepSeekProvider(http: http).fetchSpend(FakeKeys.credentials(.deepseek), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url.absoluteString == "https://api.deepseek.com/user/balance")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.deepseek)")
        #expect(snapshot.balance == .usd(Decimal(string: "18.42")!))
    }

    @Test func aYuanAccountShowsYuan() async throws {
        let body = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await DeepSeekProvider(http: http).fetchSpend(FakeKeys.credentials(.deepseek), now: testNow)
        let balance = try #require(snapshot.balance)
        #expect(balance == Balance(remaining: 110, unit: .money(Currency("CNY"))))
        #expect(BalanceText.remaining(balance) == "CNY 110.00 left")
    }

    @Test func withBothCurrenciesItShowsDollars() async throws {
        let body = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"5.00"},{"currency":"USD","total_balance":"2.50"}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await DeepSeekProvider(http: http).fetchSpend(FakeKeys.credentials(.deepseek), now: testNow)
        #expect(snapshot.balance == .usd(Decimal(string: "2.5")!))
    }

    @Test func noBalancesIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"is_available":false,"balance_infos":[]}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await DeepSeekProvider(http: http).fetchSpend(FakeKeys.credentials(.deepseek), now: testNow)
        }
    }

    @Test func showsDeepSeeksMessageWhenItSendsOne() async {
        let body = #"{"error":{"message":"Insufficient Balance","type":"payment_required"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 402, json: body) }
        await #expect(throws: SpendError.rejected(status: 402, detail: "Insufficient Balance")) {
            try await DeepSeekProvider(http: http).fetchSpend(FakeKeys.credentials(.deepseek), now: testNow)
        }
    }
}
// swiftlint:enable line_length
