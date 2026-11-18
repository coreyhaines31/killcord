import Foundation
@testable import KillCordCore
import Testing

@Suite struct OpenAIAttributionTests {
    let start = ISO8601.date("2026-11-13T00:00:00Z")!

    func client() throws -> MockHTTPClient {
        let page1 = try json("openai-attribution-costs-by-project-page1.json")
        let page2 = try json("openai-attribution-costs-by-project-page2.json")
        let total = try json("openai-attribution-costs-total.json")
        let byUser = try json("openai-attribution-costs-by-user.json")
        let usage = try json("openai-attribution-usage-by-key.json")
        let projects = try json("openai-projects.json")
        let alphaKeys = try json("openai-project-keys-alpha.json")
        let betaKeys = try json("openai-project-keys-beta.json")
        return MockHTTPClient { request in
            switch request.path {
            case "/v1/organization/usage/completions": return usage
            case "/v1/organization/projects": return projects
            case "/v1/organization/projects/proj_TESTalpha/api_keys": return alphaKeys
            case "/v1/organization/projects/proj_TESTbeta/api_keys": return betaKeys
            default: break
            }
            switch request.query("group_by") {
            case []: return total
            case ["user_id"]: return byUser
            default: return request.query("page") == ["page_TEST_2"] ? page2 : page1
            }
        }
    }

    @Test func sendsGetRequestsWithTheKeyOnlyInTheHeader() async throws {
        let http = try client()
        _ = try await OpenAIAttributionProvider(http: http).costReport(
            FakeKeys.credentials(.openai), by: .project, from: start, to: testNow, now: testNow)
        #expect(http.requests.count == 3)
        for request in http.requests {
            #expect(request.method == .get)
            #expect(request.url.host == "api.openai.com")
            #expect(request.path == "/v1/organization/costs")
            #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.openai)")
            #expect(request.query("start_time") == ["1794528000"])
            #expect(request.query("end_time") == ["1794787200"])
            #expect(request.query("bucket_width") == ["1d"])
            #expect(request.query("limit") == ["180"])
            #expect(!request.url.absoluteString.contains(FakeKeys.openai))
        }
        #expect(http.requests[0].query("group_by") == ["project_id"])
        #expect(http.requests[1].query("page") == ["page_TEST_2"])
        #expect(http.requests[2].query("group_by").isEmpty)
    }

    @Test func reconcilesByProjectWithExactDecimals() async throws {
        let report = try await OpenAIAttributionProvider(http: try client()).costReport(
            FakeKeys.credentials(.openai), by: .project, from: start, to: testNow, now: testNow)
        #expect(report.meaningVerified)
        // JSON numbers 0.1 and 0.2 stay exact: no binary floating point anywhere.
        #expect(report.unassigned.amount(in: .usd) == usd("0.2"))
        #expect(report.providerTotal.amount(in: .usd) == usd("22.945679"))
        #expect(report.reconciles)
        let beta = AttributionUnitRef(kind: .project, externalID: "proj_TESTbeta")
        #expect(report.byUnit[beta]?.amount(in: .usd) == usd("0.100001"))
        #expect(report.dataRefreshedAt == nil)
    }

    @Test func userGroupingIsMarkedUnverified() async throws {
        let report = try await OpenAIAttributionProvider(http: try client()).costReport(
            FakeKeys.credentials(.openai), by: .user, from: start, to: testNow, now: testNow)
        #expect(report.dimension == .user)
        #expect(!report.meaningVerified)
        #expect(report.reconciles)
        #expect(report.unassigned.amount(in: .usd) == usd("0.645678"))
    }

    @Test func usageByKey() async throws {
        let http = try client()
        let usage = try await OpenAIAttributionProvider(http: http).usage(
            FakeKeys.credentials(.openai), by: .apiKey, from: start, to: testNow, now: testNow)
        #expect(http.requests.first?.query("limit") == ["31"])
        #expect(http.requests.first?.query("group_by") == ["api_key_id"])
        #expect(usage.count == 2)
        #expect(usage[0].unit == AttributionUnitRef(kind: .apiKey, externalID: "key_TESTone"))
        #expect(usage[0].inputTokens == 1200)
        #expect(usage[0].cachedInputTokens == 200)
        #expect(usage[0].requests == 4)
        #expect(usage[1].unit == nil)
    }

    @Test func listsProjectsAndKeysWithOwners() async throws {
        let http = try client()
        let units = try await OpenAIAttributionProvider(http: http).units(FakeKeys.credentials(.openai))
        #expect(http.requests.allSatisfy { $0.method == .get })
        #expect(http.requests.first?.query("include_archived") == ["true"])
        #expect(units.filter { $0.kind == .project }.map(\.status) == ["active", "archived"])
        let keys = units.filter { $0.kind == .apiKey }
        #expect(keys.map(\.keyHint) == ["Ending in wxyz", "Ending in 1234"])
        #expect(keys[0].ownerEmail == "ava@example.test")
        #expect(keys[0].parentID == "proj_TESTalpha")
        #expect(keys[1].ownerEmail == nil)
        #expect(keys[1].expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
        let encoded = try #require(String(bytes: try JSONEncoder().encode(units), encoding: .utf8))
        #expect(!encoded.contains("sk-proj") && !encoded.contains("sk-svcacct"))
    }

    @Test func errorsNeverContainTheKey() async throws {
        for response in SecretSafetyTests.hostileResponses(echo: FakeKeys.openai) {
            let provider = OpenAIAttributionProvider(http: MockHTTPClient { _ in response })
            do {
                _ = try await provider.costReport(FakeKeys.credentials(.openai), by: .user, from: start, to: testNow,
                                                  now: testNow)
                Issue.record("expected an error for status \(response.status)")
            } catch {
                #expect(!String(describing: error).contains(FakeKeys.openai))
            }
            do {
                _ = try await provider.units(FakeKeys.credentials(.openai))
                Issue.record("expected an error for status \(response.status)")
            } catch {
                #expect(!String(describing: error).contains(FakeKeys.openai))
            }
        }
    }
}
