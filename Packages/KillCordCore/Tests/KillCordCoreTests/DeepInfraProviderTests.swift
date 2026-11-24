// Fixtures follow DeepInfra's documented schema: https://docs.deepinfra.com/api-reference/billing/usage
// and its scope error: https://docs.deepinfra.com/account/authentication.md#scopes
import Foundation
@testable import KillCordCore
import Testing

@Suite struct DeepInfraProviderTests {
    @Test func readsThisMonthsTotalInCents() async throws {
        let http = MockHTTPClient(routes: ["/payment/usage": try json("deepinfra-payment-usage.json")])
        let snapshot = try await DeepInfraProvider(http: http).fetchSpend(FakeKeys.credentials(.deepinfra),
                                                                         now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.deepinfra.com/payment/usage?from=2026.11")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.deepinfra)")
        #expect(snapshot.month == usd("12.34"))
        #expect(snapshot.today == nil && snapshot.balance == nil)
    }

    @Test func noMonthYetIsZero() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"months":[],"initial_month":"2026.11"}"#) }
        let snapshot = try await DeepInfraProvider(http: http).fetchSpend(FakeKeys.credentials(.deepinfra),
                                                                         now: testNow)
        #expect(snapshot.month == usd("0"))
    }

    @Test func anotherMonthIsAnUnexpectedResponse() async {
        let body = #"{"months":[{"period":"2026.10","interval":{},"items":[],"total_cost":500}],"initial_month":"2025.03"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await DeepInfraProvider(http: http).fetchSpend(FakeKeys.credentials(.deepinfra), now: testNow)
        }
    }

    @Test func aKeyWithoutBillingReadNamesTheScope() async {
        let body = #"{"detail":{"error":"this API key does not have the 'billing:read' scope"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: body) }
        do {
            _ = try await DeepInfraProvider(http: http).fetchSpend(FakeKeys.credentials(.deepinfra), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error.message(for: .deepinfra).contains("billing:read"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func aMissingKeyNeverReachesTheNetwork() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        await #expect(throws: SpendError.notConfigured) {
            try await DeepInfraProvider(http: http).fetchSpend(ProviderCredentials(provider: .deepinfra, values: [:]),
                                                               now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func theKeyIsScopedToBillingRead() {
        #expect(ProviderID.deepinfra.keyPower == .readOnly)
    }

    @Test func monthOnlySpendCountsTheMonthNotTheDay() {
        let capability = ProviderID.deepinfra.info.capability
        #expect(capability == .monthDollars)
        #expect(capability.countsMonth && !capability.countsToday && !capability.showsBalance)
    }
}
