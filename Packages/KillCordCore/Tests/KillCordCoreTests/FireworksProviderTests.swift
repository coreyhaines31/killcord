// Fixtures follow Fireworks' documented schemas (it gives no examples):
// https://docs.fireworks.ai/api-reference/get-billing-summary, https://docs.fireworks.ai/api-reference/list-accounts,
// https://docs.fireworks.ai/api-reference/get-quota
import Foundation
@testable import KillCordCore
import Testing

@Suite struct FireworksProviderTests {
    func client(today: String = #"{"lineItems":[{"totalCost":{"currencyCode":"USD","units":"2","nanos":50000000}}]}"#)
        throws -> MockHTTPClient {
        let accounts = try json("fireworks-accounts.json")
        let month = try json("fireworks-billing-summary-month.json")
        return MockHTTPClient { request in
            if request.url.path == "/v1/accounts" { return accounts }
            if request.url.path.hasSuffix("/quotas/monthly-spend-usd") {
                return HTTPResponse(status: 200, json: #"{"name":"accounts/kc-test/quotas/monthly-spend-usd","#
                    + #""value":"200","maxValue":"1000","usage":41.5}"#)
            }
            return request.query("startTime") == ["2026-11-01T00:00:00Z"] ? month : HTTPResponse(status: 200, json: today)
        }
    }

    @Test func findsTheAccountAndReadsTodayAndThisMonth() async throws {
        let http = try client()
        let snapshot = try await FireworksProvider(http: http).fetchSpend(FakeKeys.credentials(.fireworks), now: testNow)
        #expect(http.requests.map(\.url.path) == ["/v1/accounts", "/v1/accounts/kc-test/billing/summary",
                                                   "/v1/accounts/kc-test/billing/summary"])
        #expect(http.requests.allSatisfy { $0.url.host == "api.fireworks.ai" })
        #expect(http.requests.allSatisfy { $0.headers["Authorization"] == "Bearer \(FakeKeys.fireworks)" })
        #expect(http.requests[1].query("endTime") == ["2026-11-16T00:00:00Z"])
        #expect(http.requests[2].query("startTime") == ["2026-11-15T00:00:00Z"])
        #expect(snapshot.month == usd("12.75"))
        #expect(snapshot.today == usd("2.05"))
    }

    @Test func noLineItemsIsZero() async throws {
        let http = try client(today: "{}")
        let snapshot = try await FireworksProvider(http: http).fetchSpend(FakeKeys.credentials(.fireworks), now: testNow)
        #expect(snapshot.today == usd("0"))
    }

    @Test func anotherCurrencyIsUnexpected() async throws {
        let http = try client(today: #"{"lineItems":[{"totalCost":{"currencyCode":"EUR","units":"1"}}]}"#)
        await #expect(throws: SpendError.unexpectedResponse) {
            try await FireworksProvider(http: http).fetchSpend(FakeKeys.credentials(.fireworks), now: testNow)
        }
    }

    @Test func aSavedAccountIDSkipsTheLookupAndMustLookLikeAnID() async throws {
        let http = try client()
        let saved = ProviderCredentials(provider: .fireworks, values: ["apiKey": FakeKeys.fireworks,
                                                                        "accountID": "kc-test"])
        _ = try await FireworksProvider(http: http).fetchSpend(saved, now: testNow)
        #expect(!http.requests.map(\.url.path).contains("/v1/accounts"))
        let bad = ProviderCredentials(provider: .fireworks, values: ["apiKey": FakeKeys.fireworks,
                                                                      "accountID": "../users"])
        await #expect(throws: SpendError.requiresSetup("the account ID doesn't look right. Copy it from the "
            + "Fireworks dashboard.")) {
            try await FireworksProvider(http: http).fetchSpend(bad, now: testNow)
        }
    }

    @Test func confirmsTheMonthlySpendLimit() async throws {
        let caps = await FireworksProvider(http: try client()).verifyCaps(FakeKeys.credentials(.fireworks),
                                                                           now: testNow)
        #expect(caps == [CapVerification(capID: FireworksProvider.spendLimitCapID,
                                         status: .on("Fireworks reports a monthly spend limit of $200.00. At it, "
                                            + "API requests pause."),
                                         checkedAt: testNow)])
    }
}
