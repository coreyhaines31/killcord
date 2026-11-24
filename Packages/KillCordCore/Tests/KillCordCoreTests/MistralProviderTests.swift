// Fixtures follow Mistral's documented schema: https://docs.mistral.ai/api/endpoint/beta/admin/billing
import Foundation
@testable import KillCordCore
import Testing

@Suite struct MistralProviderTests {
    static let limits = #"{"limits":{"completion":{"monthly_limit_reached":false,"no_monthly_limit":false,"#
        + #""total_usage":41.5,"usage":40,"usage_limit":500,"vibe_usage":1.5},"currency":"USD","#
        + #""last_payment_failure":false,"last_payment_failure_protection":null}}"#

    @Test func readsUsageAgainstTheLimitAsThisMonth() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: Self.limits) }
        let snapshot = try await MistralProvider(http: http).fetchSpend(FakeKeys.credentials(.mistral), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.mistral.ai/v1/admin/spend-limit")
        #expect(request.headers["x-api-key"] == FakeKeys.mistral)
        #expect(snapshot.month == usd("41.5"))
        #expect(snapshot.today == nil)
    }

    @Test func euroAccountsReadInEuros() async throws {
        let body = Self.limits.replacingOccurrences(of: #""currency":"USD""#, with: #""currency":"EUR""#)
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await MistralProvider(http: http).fetchSpend(FakeKeys.credentials(.mistral), now: testNow)
        #expect(snapshot.month == Money(decimal("41.5"), Currency("EUR")))
    }

    @Test func theDocumentedExampleHasNoUsageSoItIsUnexpected() async {
        let body = #"{"limits":{"completion":{"monthly_limit_reached":false},"currency":"USD"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await MistralProvider(http: http).fetchSpend(FakeKeys.credentials(.mistral), now: testNow)
        }
    }

    @Test func confirmsTheSpendingLimit() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: Self.limits) }
        let caps = await MistralProvider(http: http).verifyCaps(FakeKeys.credentials(.mistral), now: testNow)
        #expect(caps == [CapVerification(capID: MistralProvider.spendLimitCapID,
                                         status: .on("Mistral reports a monthly spending limit of $500.00."),
                                         checkedAt: testNow)])
    }

    @Test func aReachedLimitIsEnforced() async {
        let body = Self.limits.replacingOccurrences(of: #""monthly_limit_reached":false"#,
                                                    with: #""monthly_limit_reached":true"#)
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let caps = await MistralProvider(http: http).verifyCaps(FakeKeys.credentials(.mistral), now: testNow)
        guard case .enforced = caps.first?.status else {
            Issue.record("Expected enforced, got \(caps)")
            return
        }
    }
}
