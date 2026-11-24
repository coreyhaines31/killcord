// Fixtures follow LlamaCloud's documented schemas (its examples are placeholders):
// https://admin.api.llamaindex.ai/api/resources/organizations/methods/get_usage
// https://admin.api.llamaindex.ai/api/resources/organizations/methods/list
import Foundation
@testable import KillCordCore
import Testing

@Suite struct LlamaCloudProviderTests {
    func client() throws -> MockHTTPClient {
        MockHTTPClient(routes: [
            "/api/v2/organizations": try json("llamacloud-organizations.json"),
            "/api/v1/organizations/org_0123456789abcdef/usage": try json("llamacloud-usage.json")
        ])
    }

    @Test func findsTheOnlyOrganizationAndReadsThisPeriodsInvoice() async throws {
        let http = try client()
        let snapshot = try await LlamaCloudProvider(http: http).fetchSpend(FakeKeys.credentials(.llamacloud),
                                                                            now: testNow)
        #expect(http.requests.map(\.url.absoluteString) == [
            "https://api.cloud.llamaindex.ai/api/v2/organizations",
            "https://api.cloud.llamaindex.ai/api/v1/organizations/org_0123456789abcdef/usage"
                + "?get_current_invoice_total=true"
        ])
        #expect(http.requests.allSatisfy { $0.headers["Authorization"] == "Bearer \(FakeKeys.llamacloud)" })
        #expect(snapshot.month == usd("123.45"))
        #expect(snapshot.today == nil)
        #expect(snapshot.monthKind == .billingPeriod(start: try #require(ISO8601.date("2026-11-03T00:00:00Z"))))
    }

    @Test func aSavedOrganizationAndTheEURegionSkipTheLookup() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .llamacloud, values: [
            "apiKey": FakeKeys.llamacloud, "organizationID": "org_0123456789abcdef", "region": "EU"
        ])
        _ = try await LlamaCloudProvider(http: http).fetchSpend(credentials, now: testNow)
        #expect(http.requests.map(\.url.host) == ["api.cloud.eu.llamaindex.ai"])
    }

    @Test func severalOrganizationsAskForTheID() async {
        let body = #"{"items":[{"id":"org_a","name":"a"},{"id":"org_b","name":"b"}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.requiresSetup("this key can see 2 organizations. Add the organization ID "
            + "to choose one.")) {
            try await LlamaCloudProvider(http: http).fetchSpend(FakeKeys.credentials(.llamacloud), now: testNow)
        }
    }

    @Test func anOrganizationIDThatIsntAnIDNeverReachesThePath() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        let credentials = ProviderCredentials(provider: .llamacloud, values: [
            "apiKey": FakeKeys.llamacloud, "organizationID": "../projects"
        ])
        await #expect(throws: SpendError.requiresSetup("the organization ID doesn't look right. Copy it from "
            + "Organization Settings.")) {
            try await LlamaCloudProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func confirmsTheMonthlyInvoiceLimit() async throws {
        let caps = await LlamaCloudProvider(http: try client()).verifyCaps(FakeKeys.credentials(.llamacloud),
                                                                            now: testNow)
        #expect(caps == [CapVerification(capID: LlamaCloudProvider.spendLimitCapID,
                                         status: .on("LlamaCloud reports a monthly invoice limit of $500.00."),
                                         checkedAt: testNow)])
    }

    @Test func aReachedLimitIsEnforced() async throws {
        var usage = try #require(String(bytes: fixture("llamacloud-usage.json"), encoding: .utf8))
        usage = usage.replacingOccurrences(of: #""active_alerts": []"#,
                                           with: #""active_alerts": ["plan_spend_limit_exceeded"]"#)
        let body = usage
        let http = MockHTTPClient { request in
            request.url.path.hasSuffix("/usage") ? HTTPResponse(status: 200, json: body)
                : HTTPResponse(status: 200, json: #"{"items":[{"id":"org_0123456789abcdef","name":"kc"}]}"#)
        }
        let caps = await LlamaCloudProvider(http: http).verifyCaps(FakeKeys.credentials(.llamacloud), now: testNow)
        guard case .enforced = caps.first?.status else {
            Issue.record("Expected enforced, got \(caps)")
            return
        }
    }

    @Test func showsLlamaCloudsDetail() async {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 404, json: #"{"detail":"Organization org_0123456789abcdef not found"}"#)
        }
        await #expect(throws: SpendError.rejected(status: 404,
                                                  detail: "Organization org_0123456789abcdef not found")) {
            try await LlamaCloudProvider(http: http).fetchSpend(FakeKeys.credentials(.llamacloud), now: testNow)
        }
    }
}
