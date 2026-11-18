import Foundation
@testable import KillCordCore
import Testing

@Suite struct VercelChargesBreakdownTests {
    let start = ISO8601.date("2026-11-01T00:00:00Z")!

    func client(_ name: String = "vercel-charges-by-project.jsonl") throws -> MockHTTPClient {
        let body = try fixture(name)
        return MockHTTPClient { _ in HTTPResponse(status: 200, headers: ["content-type": "application/jsonl"], body: body) }
    }

    @Test func sendsOneGetWithTheTokenOnlyInTheHeader() async throws {
        let http = try client()
        _ = try await VercelChargesBreakdown(http: http).projectReport(
            FakeKeys.credentials(.vercel), from: start, to: testNow, now: testNow)
        #expect(http.requests.count == 1)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.host == "api.vercel.com")
        #expect(request.path == "/v1/billing/charges")
        #expect(request.query("from") == ["2026-11-01T00:00:00Z"])
        #expect(request.query("to") == ["2026-11-16T00:00:00Z"])
        #expect(request.query("teamId") == ["team_x"])
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.vercel)")
        #expect(!request.url.absoluteString.contains(FakeKeys.vercel))
    }

    @Test func reconcilesByProjectToTheCent() async throws {
        let report = try await VercelChargesBreakdown(http: try client()).projectReport(
            FakeKeys.credentials(.vercel), from: start, to: testNow, now: testNow)
        #expect(report.provider == .vercel)
        #expect(report.dimension == .project)
        #expect(report.providerTotal.amount(in: .usd) == usd("125.020001"))
        #expect(report.reconciles)
        let unit = { AttributionUnitRef(kind: .project, externalID: $0) }
        #expect(report.byUnit[unit("prj_TESTweb")]?.amount(in: .usd) == usd("124.42"))
        #expect(report.byUnit[unit("prj_TESTapi")]?.amount(in: .usd) == usd("0.000001"))
        // Tags sent as a JSON-encoded string are still read.
        #expect(report.byUnit[unit("prj_TESTdocs")]?.amount(in: .usd) == usd("0.1"))
        // A team-level charge and the docs' `"Tags": "value"` shape are Unassigned, never guessed.
        #expect(report.unassigned.amount(in: .usd) == usd("0.5"))
        #expect(report.units.map(\.externalID) == ["prj_TESTapi", "prj_TESTdocs", "prj_TESTweb"])
        #expect(report.units.first { $0.externalID == "prj_TESTweb" }?.label == "web")
    }

    @Test func matchesTheMacAppsMonthTotalForTheSameCharges() async throws {
        let snapshot = try await VercelProvider(http: try client("vercel-charges.jsonl")).fetchSpend(
            FakeKeys.credentials(.vercel), now: testNow)
        let report = try await VercelChargesBreakdown(http: try client("vercel-charges.jsonl")).projectReport(
            FakeKeys.credentials(.vercel), from: start, to: testNow, now: testNow)
        #expect(report.providerTotal.amount(in: .usd) == snapshot.month)
        #expect(report.reconciles)
    }

    @Test func splitsRangesLongerThanAYear() async throws {
        let http = try client()
        _ = try await VercelChargesBreakdown(http: http).projectReport(
            FakeKeys.credentials(.vercel), from: ISO8601.date("2025-01-01T00:00:00Z")!, to: testNow, now: testNow)
        #expect(http.requests.count == 2)
        #expect(http.requests[0].query("to") == http.requests[1].query("from"))
    }

    @Test func aDroppedRowShowsAsAGap() throws {
        let charges = try VercelChargesBreakdown.parse(try fixture("vercel-charges-by-project.jsonl"))
        var report = try VercelChargesBreakdown.report(charges, range: DateInterval(start: start, end: testNow))
        report.rows.removeLast()
        #expect(!report.reconciles)
        #expect(report.gap.amount(in: .usd) == usd("0.2"))
    }

    @Test func errorsNeverContainTheToken() async throws {
        for response in SecretSafetyTests.hostileResponses(echo: FakeKeys.vercel) {
            do {
                _ = try await VercelChargesBreakdown(http: MockHTTPClient { _ in response }).projectReport(
                    FakeKeys.credentials(.vercel), from: start, to: testNow, now: testNow)
                Issue.record("expected an error for status \(response.status)")
            } catch {
                #expect(!String(describing: error).contains(FakeKeys.vercel))
            }
        }
    }
}
