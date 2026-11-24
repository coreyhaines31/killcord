// Fixtures follow Hugging Face's documented schema: https://huggingface.co/docs/inference-providers/pricing and
// https://huggingface.co/.well-known/openapi.json (/api/organizations/{name}/billing/usage/inference)
import Foundation
@testable import KillCordCore
import Testing

@Suite struct HuggingFaceProviderTests {
    static let days = #"[{"period":"2026-11-03T00:00:00.000Z","usage":[{"user":"ada","model":"m","provider":"p","#
        + #""requestCount":3,"costCents":120,"inputTokens":0,"outputTokens":0,"cachedInputTokens":0}]},"#
        + #"{"period":"2026-11-15T00:00:00.000Z","usage":[{"user":"ada","model":"m","provider":"p","requestCount":1,"#
        + #""costCents":45,"inputTokens":0,"outputTokens":0,"cachedInputTokens":0},{"user":null,"model":null,"#
        + #""provider":"q","requestCount":1,"costCents":5,"inputTokens":0,"outputTokens":0,"cachedInputTokens":0}]}]"#

    @Test func addsUpCentsByDay() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: Self.days) }
        let snapshot = try await HuggingFaceProvider(http: http).fetchSpend(FakeKeys.credentials(.huggingface),
                                                                             now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url.host == "huggingface.co")
        #expect(request.url.path == "/api/organizations/kc-test-org/billing/usage/inference")
        #expect(request.query("startDate") == ["2026-11-01T00:00:00Z"])
        #expect(request.query("endDate") == ["2026-11-15T18:30:00Z"])
        #expect(request.query("limit") == ["31"])
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.huggingface)")
        #expect(snapshot.month == usd("1.70"))
        #expect(snapshot.today == usd("0.50"))
    }

    @Test func followsTheNextLinkOnlyOnHuggingFace() async throws {
        let next = "https://huggingface.co/api/organizations/kc-test-org/billing/usage/inference?cursor=2"
        let http = MockHTTPClient { request in
            request.query("cursor") == ["2"]
                ? HTTPResponse(status: 200, json: #"[{"period":"2026-11-02T00:00:00.000Z","usage":[{"costCents":100}]}]"#)
                : HTTPResponse(status: 200, json: Self.days, headers: ["Link": "<\(next)>; rel=\"next\""])
        }
        let snapshot = try await HuggingFaceProvider(http: http).fetchSpend(FakeKeys.credentials(.huggingface),
                                                                             now: testNow)
        #expect(http.requests.count == 2)
        #expect(snapshot.month == usd("2.70"))
        #expect(HuggingFaceProvider.nextLink("<https://evil.example.com/x>; rel=\"next\"") == nil)
    }

    @Test func anOrganizationNameThatIsntANameNeverReachesThePath() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: "[]") }
        let credentials = ProviderCredentials(provider: .huggingface, values: ["apiKey": FakeKeys.huggingface,
                                                                                "organization": "a/../b"])
        await #expect(throws: SpendError.requiresSetup("the organization name doesn't look right. Use the name in "
            + "its huggingface.co address.")) {
            try await HuggingFaceProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func showsHuggingFacesOwnError() async {
        let body = #"{"error":"This feature requires an Enterprise plan"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 402, json: body) }
        await #expect(throws: SpendError.rejected(status: 402, detail: "This feature requires an Enterprise plan")) {
            try await HuggingFaceProvider(http: http).fetchSpend(FakeKeys.credentials(.huggingface), now: testNow)
        }
    }
}
