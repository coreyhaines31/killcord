import Foundation
@testable import KillCordCore
import Testing

@Suite struct NeonProjectBreakdownTests {
    let start = ISO8601.date("2026-11-01T00:00:00Z")!

    func client(_ name: String = "neon-consumption-by-project.json") throws -> MockHTTPClient {
        let body = try json(name)
        return MockHTTPClient { _ in body }
    }

    @Test func sendsOneGetWithTheKeyOnlyInTheHeader() async throws {
        let http = try client()
        _ = try await NeonProjectBreakdown(http: http).projectUsage(
            FakeKeys.credentials(.neon), from: start, to: testNow)
        // Two projects is a short page, so there is no second request.
        #expect(http.requests.count == 1)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.host == "console.neon.tech")
        #expect(request.path == "/api/v2/consumption_history/v2/projects")
        #expect(request.query("granularity") == ["daily"])
        #expect(request.query("org_id") == ["org-cool-cloud-123"])
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.neon)")
        #expect(!request.url.absoluteString.contains(FakeKeys.neon))
    }

    @Test func splitsUsageByProjectInRawUnits() async throws {
        let usage = try await NeonProjectBreakdown(http: try client()).projectUsage(
            FakeKeys.credentials(.neon), from: start, to: testNow)
        let alpha = AttributionUnitRef(kind: .project, externalID: "test-alpha-11111111")
        let beta = AttributionUnitRef(kind: .project, externalID: "test-beta-22222222")
        #expect(usage.byUnit[alpha]?["compute_unit_seconds"] == decimal("9000.5"))
        #expect(usage.byUnit[beta]?["compute_unit_seconds"] == decimal("0.1"))
        #expect(usage.byUnit[beta]?["public_network_transfer_bytes"] == 1414)
        #expect(usage.byUnit[nil] == nil)
        #expect(usage.rawUnits["compute_unit_seconds"] == "CU-seconds")
        #expect(usage.units.map(\.externalID) == ["test-alpha-11111111", "test-beta-22222222"])
    }

    @Test(arguments: ["neon-consumption-by-project.json", "neon-consumption-page1.json"])
    func unitsReconcileWithTheMacAppsTotals(_ name: String) async throws {
        let usage = try await NeonProjectBreakdown(http: try client(name)).projectUsage(
            FakeKeys.credentials(.neon), from: start, to: testNow)
        let snapshot = try await NeonProvider(http: try client(name)).fetchSpend(FakeKeys.credentials(.neon), now: testNow)
        for metric in NeonProvider.metrics {
            let parts = (usage.totals[metric.id] ?? 0) / metric.divisor
            #expect(snapshot.usage.first { $0.id == metric.id }?.value == parts, "\(metric.id)")
        }
        // Per-project parts sum to the per-metric total exactly.
        for (metric, total) in usage.totals {
            let parts = usage.byUnit.values.reduce(Decimal(0)) { $0 + ($1[metric] ?? 0) }
            #expect(parts == total)
        }
    }

    @Test func carriesNoMoneyAtAll() async throws {
        let usage = try await NeonProjectBreakdown(http: try client()).projectUsage(
            FakeKeys.credentials(.neon), from: start, to: testNow)
        let encoded = try #require(String(bytes: try JSONEncoder().encode(usage), encoding: .utf8))
        #expect(!encoded.contains("currency"))
        #expect(!encoded.contains("amount"))
        #expect(!Mirror(reflecting: usage.rows[0]).children.contains { $0.value is Money })
    }

    @Test func errorsNeverContainTheKey() async throws {
        for response in SecretSafetyTests.hostileResponses(echo: FakeKeys.neon) {
            do {
                _ = try await NeonProjectBreakdown(http: MockHTTPClient { _ in response }).projectUsage(
                    FakeKeys.credentials(.neon), from: start, to: testNow)
                Issue.record("expected an error for status \(response.status)")
            } catch {
                #expect(!String(describing: error).contains(FakeKeys.neon))
            }
        }
    }
}
