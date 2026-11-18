import Foundation
@testable import KillCordCore
import Testing

@Suite struct GoogleBillingBreakdownTests {
    /// The breakdown query is the POST whose SQL selects unit_id; the other POST is GoogleCloudProvider's total.
    func client(breakdown: String, pendingFirst: Bool = false) throws -> MockHTTPClient {
        let token = try json("google-token.json")
        let total = try json("google-query.json")
        let grouped = try json(breakdown)
        let pending = try json("google-query-pending.json")
        let lock = NSLock()
        nonisolated(unsafe) var sentPending = false
        return MockHTTPClient { request in
            if request.url.host == "oauth2.googleapis.com" { return token }
            if request.method == .get { return grouped }
            let sql = request.body.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
            guard sql.contains("unit_id") else { return total }
            return lock.withLock {
                if pendingFirst && !sentPending {
                    sentPending = true
                    return pending
                }
                return grouped
            }
        }
    }

    func body(_ request: HTTPRequest) throws -> [String: Any] {
        let data = try #require(request.body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func onlyWritesAreTheTokenExchangeAndReadQueries() async throws {
        let http = try client(breakdown: "google-breakdown-by-label.json")
        _ = try await GoogleBillingBreakdown(http: http, signer: FakeSigner()).costReport(
            FakeKeys.credentials(.google), by: .projectLabel("team"), now: testNow)
        let queries = http.requests.filter { $0.url.host == "bigquery.googleapis.com" }
        #expect(queries.count == 2)
        for query in queries {
            #expect(query.method == .post)
            #expect(query.path == "/bigquery/v2/projects/kc-billing/queries")
            #expect(query.headers["Authorization"] == "Bearer ya29.TEST-ACCESS-TOKEN")
        }
        let grouped = try body(queries[0])
        let sql = try #require(grouped["query"] as? String)
        #expect(sql.contains("UNNEST(project.labels) l WHERE l.key = @label_key"))
        #expect(sql.contains("WHERE invoice.month = @invoice_month"))
        // The label key travels as a parameter, never in the SQL text.
        #expect(!sql.contains("team"))
        let parameters = try #require(grouped["queryParameters"] as? [[String: Any]])
        let values = parameters.compactMap { ($0["parameterValue"] as? [String: String])?["value"] }
        #expect(values.sorted() == ["202611", "team"])
        let hosts = Set(http.requests.compactMap(\.url.host))
        #expect(hosts == ["oauth2.googleapis.com", "bigquery.googleapis.com"])
    }

    @Test func reconcilesByProjectToTheCent() async throws {
        let report = try await GoogleBillingBreakdown(
            http: try client(breakdown: "google-breakdown-by-project.json"), signer: FakeSigner()
        ).costReport(FakeKeys.credentials(.google), by: .project, now: testNow)
        #expect(report.dimension == .project)
        #expect(report.providerTotal.amount(in: .usd) == usd("42.137215"))
        #expect(report.reconciles)
        #expect(report.byUnit[AttributionUnitRef(kind: .project, externalID: "kc-web-test")]?.amount(in: .usd)
            == usd("30.137214"))
        #expect(report.unassigned.amount(in: .usd) == usd("0.000001"))
        #expect(report.units.map(\.label) == ["Data (test)", "Web (test)"])
        #expect(report.dataRefreshedAt == ISO8601.date("2026-11-15T11:00:00Z"))
        // Google's billing month follows US Pacific time.
        #expect(report.rangeStart == ISO8601.date("2026-11-01T07:00:00Z"))
    }

    @Test func labelsBecomeKeyValueUnitsAndUnlabelledSpendIsUnassigned() async throws {
        let report = try await GoogleBillingBreakdown(
            http: try client(breakdown: "google-breakdown-by-label.json"), signer: FakeSigner()
        ).costReport(FakeKeys.credentials(.google), by: .resourceLabel("env"), now: testNow)
        #expect(report.dimension == .resourceLabel)
        #expect(report.reconciles)
        let platform = AttributionUnitRef(kind: .label, externalID: "env=platform")
        #expect(report.byUnit[platform]?.amount(in: .usd) == usd("40.000001"))
        #expect(report.unassigned.amount(in: .usd) == usd("2"))
        #expect(report.units.first { $0.externalID == "env=platform" }?.label == "env: platform")
    }

    @Test func waitsForASlowQuery() async throws {
        let http = try client(breakdown: "google-breakdown-by-project.json", pendingFirst: true)
        let report = try await GoogleBillingBreakdown(http: http, signer: FakeSigner())
            .costReport(FakeKeys.credentials(.google), by: .project, now: testNow)
        #expect(report.reconciles)
        let poll = try #require(http.requests.first { $0.method == .get })
        #expect(poll.path == "/bigquery/v2/projects/kc-billing/queries/job_abc123")
        #expect(poll.query("location") == ["US"])
    }

    @Test func aRowMissingFromTheBreakdownShowsAsAGap() async throws {
        // Grouped rows from the label fixture against the same total, minus one row.
        var report = try await GoogleBillingBreakdown(
            http: try client(breakdown: "google-breakdown-by-label.json"), signer: FakeSigner()
        ).costReport(FakeKeys.credentials(.google), by: .projectLabel("team"), now: testNow)
        report.rows.removeLast()
        #expect(report.gap.amount(in: .usd) == usd("2"))
    }

    @Test(arguments: ["Team", "team; DROP TABLE x", "", String(repeating: "a", count: 64)])
    func refusesLabelKeysGoogleWouldNot(_ key: String) async throws {
        let http = try client(breakdown: "google-breakdown-by-label.json")
        await #expect(throws: SpendError.self) {
            try await GoogleBillingBreakdown(http: http, signer: FakeSigner())
                .costReport(FakeKeys.credentials(.google), by: .projectLabel(key), now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func errorsNeverContainThePrivateKey() async throws {
        for response in SecretSafetyTests.hostileResponses(echo: FakeKeys.googlePrivateKey) {
            let token = try json("google-token.json")
            let http = MockHTTPClient { request in request.url.host == "oauth2.googleapis.com" ? token : response }
            do {
                _ = try await GoogleBillingBreakdown(http: http, signer: FakeSigner())
                    .costReport(FakeKeys.credentials(.google), by: .project, now: testNow)
                Issue.record("expected an error for status \(response.status)")
            } catch {
                #expect(!String(describing: error).contains("TESTPRIVATEKEY"))
            }
        }
    }
}
