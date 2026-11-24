// Fixtures follow Browserbase's documented schemas (it gives no examples):
// https://docs.browserbase.com/reference/api/get-project-usage, https://docs.browserbase.com/reference/api/list-projects
import Foundation
@testable import KillCordCore
import Testing

@Suite struct BrowserbaseProviderTests {
    static let projects = #"[{"id":"proj_0123abcd","createdAt":"2026-01-02T03:04:05Z","updatedAt":"2026-01-02T03:04:05Z","#
        + #""name":"Default","ownerId":"org_1","defaultTimeout":300,"concurrency":3}]"#

    @Test func findsTheProjectAndReadsMinutesAndProxyData() async throws {
        let http = MockHTTPClient { request in
            request.url.path == "/v1/projects" ? HTTPResponse(status: 200, json: Self.projects)
                : HTTPResponse(status: 200, json: #"{"browserMinutes":1234,"proxyBytes":2500000000}"#)
        }
        let snapshot = try await BrowserbaseProvider(http: http).fetchSpend(FakeKeys.credentials(.browserbase),
                                                                             now: testNow)
        #expect(http.requests.map(\.url.absoluteString) == ["https://api.browserbase.com/v1/projects",
                                                            "https://api.browserbase.com/v1/projects/proj_0123abcd/usage"])
        #expect(http.requests.allSatisfy { $0.headers["X-BB-API-Key"] == FakeKeys.browserbase })
        #expect(snapshot.usage == [
            UsageMetric(id: "browserMinutes", name: "Browser time", value: 1234, unit: "minutes"),
            UsageMetric(id: "proxyData", name: "Proxy data", value: decimal("2.5"), unit: "GB")
        ])
        #expect(snapshot.month == nil && snapshot.balance == nil)
    }

    @Test func severalProjectsAskForTheID() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"[{"id":"a"},{"id":"b"}]"#) }
        await #expect(throws: SpendError.requiresSetup("this key can see 2 projects. Add the project ID to choose "
            + "one.")) {
            try await BrowserbaseProvider(http: http).fetchSpend(FakeKeys.credentials(.browserbase), now: testNow)
        }
    }

    @Test func aSavedProjectIDMustLookLikeAnID() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        let credentials = ProviderCredentials(provider: .browserbase, values: ["apiKey": FakeKeys.browserbase,
                                                                                "projectID": "a/../b"])
        await #expect(throws: SpendError.requiresSetup("the project ID doesn't look right. Copy it from the "
            + "project's settings.")) {
            try await BrowserbaseProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }
}
