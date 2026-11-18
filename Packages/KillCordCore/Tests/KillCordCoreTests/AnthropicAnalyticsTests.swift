import Foundation
@testable import KillCordCore
import Testing

@Suite struct AnthropicAnalyticsTests {
    let start = ISO8601.date("2026-11-13T00:00:00Z")!

    /// Routes like the real API: grouped or not, by dimension, and by page cursor.
    func client(byActor: Bool = false) throws -> MockHTTPClient {
        let keyPage1 = try json("anthropic-analytics-cost-by-key-page1.json")
        let keyPage2 = try json("anthropic-analytics-cost-by-key-page2.json")
        let total = try json(byActor ? "anthropic-analytics-cost-actor-total.json"
                                     : "anthropic-analytics-cost-total.json")
        let actor = try json("anthropic-analytics-cost-by-actor.json")
        let usage = try json("anthropic-analytics-usage-by-workspace.json")
        return MockHTTPClient { request in
            let groups = request.query("group_by[]")
            if request.path.hasSuffix("/analytics/usage") { return usage }
            if groups.isEmpty { return total }
            if groups.contains("actor") { return actor }
            return request.query("page") == ["page_TEST_cost_2"] ? keyPage2 : keyPage1
        }
    }

    @Test func sendsTheDocumentedCostRequest() async throws {
        let http = try client()
        _ = try await AnthropicAnalyticsProvider(http: http).costReport(
            FakeKeys.credentials(.anthropic), by: .apiKey, from: start, to: testNow, now: testNow)
        #expect(http.requests.count == 3)
        for request in http.requests {
            #expect(request.method == .get)
            #expect(request.url.host == "api.anthropic.com")
            #expect(request.path == "/v1/organizations/analytics/cost")
            #expect(request.headers["x-api-key"] == FakeKeys.anthropic)
            #expect(request.headers["anthropic-beta"] == "analytics-usage-cost-2026-08-24")
            #expect(request.headers["anthropic-version"] == "2026-10-21")
            #expect(request.query("starting_at") == ["2026-11-13T00:00:00Z"])
            // Through the end of today (a partial bucket), as whole UTC days.
            #expect(request.query("ending_at") == ["2026-11-16T00:00:00Z"])
            #expect(request.query("time_bucket_width") == ["1d"])
            #expect(request.query("order_by") == ["time"])
            #expect(request.query("limit") == ["1000"])
            #expect(!request.url.absoluteString.contains(FakeKeys.anthropic))
        }
        #expect(http.requests[0].query("group_by[]") == ["api_key_id"])
        #expect(http.requests[1].query("page") == ["page_TEST_cost_2"])
        #expect(http.requests[2].query("group_by[]").isEmpty)
    }

    @Test func reconcilesWithAnthropicsTotalToTheCent() async throws {
        let report = try await AnthropicAnalyticsProvider(http: try client()).costReport(
            FakeKeys.credentials(.anthropic), by: .apiKey, from: start, to: testNow, now: testNow)
        #expect(report.dimension == .apiKey)
        #expect(report.meaningVerified)
        #expect(report.rows.count == 6)
        // 20000.500001 cents, exactly.
        #expect(report.providerTotal.amount(in: .usd) == usd("200.00500001"))
        #expect(report.reconciles)
        #expect(report.unassigned.amount(in: .usd) == usd("1.66666667"))
        let keyA = AttributionUnitRef(kind: .apiKey, externalID: "apikey_01TESTaaaaaaaaaaaaaaaaaa")
        #expect(report.byUnit[keyA]?.amount(in: .usd) == usd("195.005"))
        // The oldest data_refreshed_at seen wins: newer data may be partial.
        #expect(report.dataRefreshedAt == ISO8601.date("2026-11-15T12:02:11Z"))
    }

    @Test func aMismatchedTotalIsReportedNotHidden() async throws {
        let http = try client()
        // One millionth of a cent less than the rows add up to.
        let wrongTotal = try json("anthropic-analytics-cost-total-off-by-one.json")
        let keyPage1 = try json("anthropic-analytics-cost-by-key-page1.json")
        let keyPage2 = try json("anthropic-analytics-cost-by-key-page2.json")
        http.setHandler { request in
            if request.query("group_by[]").isEmpty { return wrongTotal }
            return request.query("page") == ["page_TEST_cost_2"] ? keyPage2 : keyPage1
        }
        let report = try await AnthropicAnalyticsProvider(http: http).costReport(
            FakeKeys.credentials(.anthropic), by: .apiKey, from: start, to: testNow, now: testNow)
        #expect(!report.reconciles)
        #expect(report.gap.amount(in: .usd) == usd("-0.00000001"))
    }

    @Test func mapsEveryActorTypeAndSendsUnknownOnesToUnassigned() async throws {
        let report = try await AnthropicAnalyticsProvider(http: try client(byActor: true)).costReport(
            FakeKeys.credentials(.anthropic), by: .actor, from: start, to: testNow, now: testNow)
        #expect(report.reconciles)
        let kinds = Set(report.rows.compactMap(\.unit?.kind))
        #expect(kinds == [.user, .serviceAccount, .apiKey, .federated])
        // A future actor type and a null actor: $0.9975 + $0, unassigned rather than guessed.
        #expect(report.unassigned.amount(in: .usd) == usd("0.9975"))
        let ava = try #require(report.units.first { $0.kind == .user })
        #expect(ava.externalID == "user_01TESTava")
        #expect(ava.ownerEmail == "ava@example.test")
        #expect(ava.label == "Ava Example")
        let federated = try #require(report.units.first { $0.kind == .federated })
        #expect(federated.label == "AWS identity")
    }

    @Test func splitsLongRangesIntoWindowsOfAtMost31Days() async throws {
        let empty = HTTPResponse(status: 200,
                                 json: #"{"data":[],"has_more":false,"next_page":null,"data_refreshed_at":null}"#)
        let http = MockHTTPClient { _ in empty }
        let from = ISO8601.date("2026-01-01T00:00:00Z")!
        let report = try await AnthropicAnalyticsProvider(http: http).costReport(
            FakeKeys.credentials(.anthropic), by: .workspace, from: from, to: testNow, now: testNow)
        #expect(report.reconciles)
        #expect(report.dataRefreshedAt == nil)
        let windows = http.requests.filter { !$0.query("group_by[]").isEmpty }.map {
            DateInterval(start: ISO8601.date($0.query("starting_at")[0])!, end: ISO8601.date($0.query("ending_at")[0])!)
        }
        #expect(windows.count == 11)
        #expect(windows.allSatisfy { $0.duration <= 31 * 86_400 })
        #expect(windows.first?.start == from)
        #expect(windows.last?.end == ISO8601.date("2026-11-16T00:00:00Z"))
    }

    @Test func refusesHistoryAnthropicDoesNotKeep() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 500) }
        let provider = AnthropicAnalyticsProvider(http: http)
        // Before 2026-01-01.
        await #expect(throws: AttributionRangeError.self) {
            _ = try await provider.costReport(FakeKeys.credentials(.anthropic), by: .apiKey,
                                              from: ISO8601.date("2025-12-31T00:00:00Z")!, to: testNow, now: testNow)
        }
        // More than 365 days back.
        let later = ISO8601.date("2027-06-01T12:00:00Z")!
        await #expect(throws: AttributionRangeError.self) {
            _ = try await provider.costReport(FakeKeys.credentials(.anthropic), by: .apiKey,
                                              from: ISO8601.date("2026-05-01T00:00:00Z")!, to: later, now: later)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func restartsPaginationOnceWhenTheCursorExpires() async throws {
        let keyPage1 = try json("anthropic-analytics-cost-by-key-page1.json")
        let keyPage2 = try json("anthropic-analytics-cost-by-key-page2.json")
        let total = try json("anthropic-analytics-cost-total.json")
        let expired = HTTPResponse(status: 410,
                                   json: #"{"type":"error","error":{"type":"gone","message":"cursor expired"}}"#)
        let state = Counter()
        let http = MockHTTPClient { request in
            if request.query("group_by[]").isEmpty { return total }
            if request.query("page") == ["page_TEST_cost_2"] { return state.next() == 0 ? expired : keyPage2 }
            return keyPage1
        }
        let report = try await AnthropicAnalyticsProvider(http: http).costReport(
            FakeKeys.credentials(.anthropic), by: .apiKey, from: start, to: testNow, now: testNow)
        #expect(report.reconciles)
        #expect(report.rows.count == 6)
        #expect(http.requests.filter { $0.query("page").isEmpty && !$0.query("group_by[]").isEmpty }.count == 2)
    }

    @Test func usageCountsAllInputTokensAndNeverMoney() async throws {
        let usage = try await AnthropicAnalyticsProvider(http: try client()).usage(
            FakeKeys.credentials(.anthropic), by: .workspace, from: start, to: testNow, byModel: true, now: testNow)
        #expect(usage.count == 2)
        let first = try #require(usage.first)
        #expect(first.unit == AttributionUnitRef(kind: .workspace, externalID: "wrkspc_01TESTdefault"))
        #expect(first.model == "claude-opus-5-5")
        #expect(first.inputTokens == 1530)
        #expect(first.cachedInputTokens == 500)
        #expect(first.outputTokens == 300)
        #expect(first.requests == 7)
        #expect(usage[1].unit == nil)
    }

    @Test func listsUnitsWithOwnersAndOnlyTheLastFourOfAKeyHint() async throws {
        let page1 = try json("anthropic-admin-api-keys-page1.json")
        let page2 = try json("anthropic-admin-api-keys-page2.json")
        let users = try json("anthropic-admin-users.json")
        let workspaces = try json("anthropic-admin-workspaces.json")
        let http = MockHTTPClient { request in
            switch request.path {
            case "/v1/organizations/users": users
            case "/v1/organizations/workspaces": workspaces
            default: request.query("after_id") == ["apikey_01TESTaaaaaaaaaaaaaaaaaa"] ? page2 : page1
            }
        }
        let units = try await AnthropicAnalyticsProvider(http: http).units(FakeKeys.credentials(.anthropic))
        #expect(http.requests.allSatisfy { $0.method == .get && $0.headers["anthropic-beta"] == nil })
        #expect(http.requests.first { $0.path.hasSuffix("/workspaces") }?.query("include_archived") == ["true"])
        #expect(units.filter { $0.kind == .user }.count == 2)
        #expect(units.filter { $0.kind == .workspace }.map(\.status) == ["active", "archived"])
        let keys = units.filter { $0.kind == .apiKey }
        #expect(keys.count == 3)
        #expect(keys[0].keyHint == "Ending in igAA")
        #expect(keys[0].ownerEmail == "ava@example.test")
        #expect(keys[0].expiresAt == ISO8601.date("2027-03-01T00:00:00Z"))
        #expect(keys[1].ownerEmail == nil)
        #expect(keys[1].parentID == "wrkspc_01TESTdefault")
        #expect(keys[2].keyHint == nil)
        #expect(keys[2].status == "archived")
        // The hint's prefix never reaches a unit.
        let encoded = try #require(String(bytes: try JSONEncoder().encode(units), encoding: .utf8))
        #expect(!encoded.contains("sk-ant"))
    }

    @Test func errorsNeverContainTheKey() async throws {
        for response in SecretSafetyTests.hostileResponses(echo: FakeKeys.anthropic) {
            let http = MockHTTPClient { _ in response }
            let provider = AnthropicAnalyticsProvider(http: http)
            do {
                _ = try await provider.costReport(FakeKeys.credentials(.anthropic), by: .actor, from: start,
                                                  to: testNow, now: testNow)
                Issue.record("expected an error for status \(response.status)")
            } catch {
                #expect(!String(describing: error).contains(FakeKeys.anthropic))
                #expect(!error.localizedDescription.contains(FakeKeys.anthropic))
            }
            do {
                _ = try await provider.units(FakeKeys.credentials(.anthropic))
                Issue.record("expected an error for status \(response.status)")
            } catch {
                #expect(!String(describing: error).contains(FakeKeys.anthropic))
            }
        }
    }
}

/// Counts calls across the mock's Sendable handler.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}
