// swiftlint:disable line_length
// Fixtures follow SerpApi's documented response: https://serpapi.com/account-api
import Foundation
@testable import KillCordCore
import Testing

@Suite struct SerpApiProviderTests {
    @Test func readsSearchesLeftOfThePlanAndTheRenewal() async throws {
        let http = MockHTTPClient(routes: ["/account.json": try json("serpapi-account.json")])
        let snapshot = try await SerpApiProvider(http: http).fetchSpend(FakeKeys.credentials(.serpapi), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://serpapi.com/account.json?api_key=\(FakeKeys.serpapi)")
        #expect(request.headers.isEmpty)
        #expect(snapshot.balance == Balance(remaining: 5958, unit: .units("searches"), kind: .allowance, limit: 30_000,
                                            used: 24_042, resetsAt: ISO8601.date("2026-12-24T00:00:00Z")))
    }

    @Test func extraCreditsMeanThePlanSizeIsNotALimit() async throws {
        let body = #"{"plan_renewal_date":null,"searches_per_month":100,"plan_searches_left":0,"extra_credits":500,"total_searches_left":500,"this_month_usage":100}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let balance = try #require(try await SerpApiProvider(http: http).fetchSpend(FakeKeys.credentials(.serpapi), now: testNow).balance)
        #expect(balance.remaining == 500)
        #expect(balance.limit == nil)
        #expect(balance.kind == .prepaid)
        #expect(balance.resetsAt == nil)
    }

    @Test func aKeyCantAddQueryParameters() throws {
        let url = try #require(SerpApiProvider.accountURL(key: "abc&engine=google#x"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.count == 1)
        #expect(items.first?.name == "api_key")
        #expect(items.first?.value == "abc&engine=google#x")
        #expect(url.fragment == nil)
    }

    @Test func anEchoedKeyIsRemovedFromSerpApisMessage() async {
        let body = #"{"error":"Invalid API key \#(FakeKeys.serpapi). Your API key should be here: https://serpapi.com/manage-api-key"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        do {
            _ = try await SerpApiProvider(http: http).fetchSpend(FakeKeys.credentials(.serpapi), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error == .rejected(status: 400, detail: "Invalid API key [redacted]. Your API key should be here: https://serpapi.com/manage-api-key"))
            #expect(!error.message(for: .serpapi).contains(FakeKeys.serpapi))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }
}
// swiftlint:enable line_length
