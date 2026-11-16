// swiftlint:disable line_length
// Inline JSON fixtures preserve the exact provider response shape.
import Foundation
@testable import KillCordCore
import Testing

@Suite struct VercelProviderTests {
    func client() throws -> MockHTTPClient {
        let body = try fixture("vercel-charges.jsonl")
        return MockHTTPClient { _ in HTTPResponse(status: 200, headers: ["Content-Type": "application/jsonl"], body: body) }
    }

    @Test func buildsTheChargesRequest() async throws {
        let http = try client()
        _ = try await VercelProvider(http: http).fetchSpend(FakeKeys.credentials(.vercel), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.url.host == "api.vercel.com")
        #expect(request.path == "/v1/billing/charges")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.vercel)")
        #expect(request.query("from") == ["2026-11-01T00:00:00Z"])
        #expect(request.query("to") == ["2026-11-16T00:00:00Z"])
        #expect(request.query("teamId") == ["team_x"])
    }

    @Test func parsesJSONLinesWithNumbersOrStrings() async throws {
        let snapshot = try await VercelProvider(http: try client()).fetchSpend(FakeKeys.credentials(.vercel), now: testNow)
        #expect(snapshot.month == usd("124.72"))
        // No row for Nov 15 yet: not reported, not $0.
        #expect(snapshot.today == nil)
    }

    @Test func todayCountsOnceReported() async throws {
        let line = #"{"BilledCost":2.5,"BillingCurrency":"USD","ChargePeriodStart":"2026-11-15T00:00:00Z","ChargePeriodEnd":"2026-11-16T00:00:00Z"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, body: Data(line.utf8)) }
        let snapshot = try await VercelProvider(http: http).fetchSpend(FakeKeys.credentials(.vercel), now: testNow)
        #expect(snapshot.today == usd("2.5"))
    }

    @Test func omitsTeamWhenNotSet() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .vercel, values: ["token": FakeKeys.vercel])
        _ = try await VercelProvider(http: http).fetchSpend(credentials, now: testNow)
        #expect(http.requests.first?.query("teamId").isEmpty == true)
    }

    @Test func rejectsABadLine() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, body: Data("{not json}\n".utf8)) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await VercelProvider(http: http).fetchSpend(FakeKeys.credentials(.vercel), now: testNow)
        }
    }
}

@Suite struct CloudflareProviderTests {
    func client() throws -> MockHTTPClient {
        MockHTTPClient(routes: [
            "/billable-usage": try json("cloudflare-billable-usage.json"),
            "/billing/spend-policies": try json("cloudflare-spend-policies.json")
        ])
    }

    @Test func readsTheCurrentBillingPeriod() async throws {
        let http = try client()
        let snapshot = try await CloudflareProvider(http: http).fetchSpend(FakeKeys.credentials(.cloudflare), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.url.absoluteString
            == "https://api.cloudflare.com/client/v4/accounts/0123456789abcdef0123456789abcdef/billable-usage")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.cloudflare)")
        #expect(snapshot.month == usd("0.93"))
        #expect(snapshot.today == nil)
        #expect(snapshot.monthKind == .billingPeriod(start: ISO8601.date("2026-11-03T00:00:00Z")!))
    }

    @Test func rejectsAnAccountIDThatWouldChangeThePath() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .cloudflare,
                                              values: ["token": FakeKeys.cloudflare, "accountID": "../../user"])
        await #expect(throws: SpendError.notConfigured) {
            try await CloudflareProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func failedEnvelopeIsUnexpected() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"result":null,"success":false,"errors":[{"code":10000}]}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await CloudflareProvider(http: http).fetchSpend(FakeKeys.credentials(.cloudflare), now: testNow)
        }
    }

    @Test func verifiesASpendLimit() async throws {
        let results = await CloudflareProvider(http: try client()).verifyCaps(FakeKeys.credentials(.cloudflare), now: testNow)
        #expect(results.first?.capID == CloudflareProvider.spendLimitCapID)
        #expect(results.first?.status == .on("Cloudflare reports a spend limit that blocks usage: Workers at $50.00."))
    }

    @Test func reportsAnEnforcedLimit() async {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"result":[{"action":"usage_block","product_id":"workers","threshold_cents":5000,"enabled":true,"current_state":{"status":"limit_reached"}}],"success":true}"#)
        }
        let results = await CloudflareProvider(http: http).verifyCaps(FakeKeys.credentials(.cloudflare), now: testNow)
        guard case .enforced = results.first?.status else { Issue.record("Got \(results)"); return }
    }

    @Test func alertsAloneAreNotALimit() async {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"result":[{"action":"notification","product_id":"workers","threshold_cents":5000,"enabled":true}],"success":true}"#)
        }
        let results = await CloudflareProvider(http: http).verifyCaps(FakeKeys.credentials(.cloudflare), now: testNow)
        #expect(results.first?.status == .off("Cloudflare has spend alerts set, but no limit that blocks usage."))
    }
}

@Suite struct TwilioProviderTests {
    func client() throws -> MockHTTPClient {
        MockHTTPClient(routes: [
            "/Usage/Records/Today.json": try json("twilio-today.json"),
            "/Usage/Records/ThisMonth.json": try json("twilio-thismonth.json"),
            "/Usage/Triggers.json": try json("twilio-triggers.json")
        ])
    }

    @Test func asksForTotalPriceWithBasicAuth() async throws {
        let http = try client()
        let snapshot = try await TwilioProvider(http: http).fetchSpend(FakeKeys.credentials(.twilio), now: testNow)
        #expect(http.requests.map(\.path) == [
            "/2010-04-01/Accounts/\(FakeKeys.twilioSID)/Usage/Records/Today.json",
            "/2010-04-01/Accounts/\(FakeKeys.twilioSID)/Usage/Records/ThisMonth.json"
        ])
        #expect(http.requests.allSatisfy { $0.query("Category") == ["totalprice"] })
        let expected = Data("SKbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:\(FakeKeys.twilio)".utf8).base64EncodedString()
        #expect(http.requests.first?.headers["Authorization"] == "Basic \(expected)")
        #expect(snapshot.today == usd("1.087"))
        #expect(snapshot.month == usd("12.34567"))
        #expect(snapshot.dataAsOf == ISO8601.date("2026-11-15T18:02:11+00:00"))
    }

    @Test func fallsBackToTheAccountSIDAsUser() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .twilio,
                                              values: ["accountSID": FakeKeys.twilioSID, "secret": FakeKeys.twilio])
        _ = try await TwilioProvider(http: http).fetchSpend(credentials, now: testNow)
        let expected = Data("\(FakeKeys.twilioSID):\(FakeKeys.twilio)".utf8).base64EncodedString()
        #expect(http.requests.first?.headers["Authorization"] == "Basic \(expected)")
    }

    @Test func noRecordMeansZero() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"usage_records":[],"next_page_uri":null}"#) }
        let snapshot = try await TwilioProvider(http: http).fetchSpend(FakeKeys.credentials(.twilio), now: testNow)
        #expect(snapshot.today == .zero())
        #expect(snapshot.month == .zero())
    }

    @Test func rejectsAMalformedAccountSID() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .twilio, values: ["accountSID": "AC/../x", "secret": "s"])
        await #expect(throws: SpendError.notConfigured) {
            try await TwilioProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func verifiesASpendTrigger() async throws {
        let http = try client()
        let results = await TwilioProvider(http: http).verifyCaps(FakeKeys.credentials(.twilio), now: testNow)
        #expect(http.requests.first?.query("UsageCategory") == ["totalprice"])
        #expect(results.first?.status == .on("Twilio reports a usage trigger on total spend: $100.00 monthly. "
            + "Triggers alert; they don't stop usage."))
    }
}

@Suite struct NeonProviderTests {
    @Test func buildsTheConsumptionRequest() async throws {
        let http = MockHTTPClient(routes: ["/consumption_history/v2/projects": try json("neon-consumption-page1.json")])
        let snapshot = try await NeonProvider(http: http).fetchSpend(FakeKeys.credentials(.neon), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.url.host == "console.neon.tech")
        #expect(request.path == "/api/v2/consumption_history/v2/projects")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.neon)")
        #expect(request.query("from") == ["2026-11-01T00:00:00Z"])
        #expect(request.query("to") == ["2026-11-15T18:30:00Z"])
        #expect(request.query("granularity") == ["daily"])
        #expect(request.query("org_id") == ["org-cool-cloud-123"])
        #expect(request.query("limit") == ["100"])
        #expect(request.query("metrics").first?.contains("compute_unit_seconds,root_branch_bytes_month") == true)
        // A single short page: no second request.
        #expect(http.requests.count == 1)

        // Usage only: never dollars.
        #expect(snapshot.today == nil)
        #expect(snapshot.month == nil)
        let usage = Dictionary(uniqueKeysWithValues: snapshot.usage.map { ($0.id, $0) })
        #expect(usage["compute_unit_seconds"]?.value == decimal("2.5"))
        #expect(usage["compute_unit_seconds"]?.unit == "CU-hours")
        #expect(usage["root_branch_bytes_month"]?.value == decimal("0.5"))
        #expect(usage["public_network_transfer_bytes"]?.value == decimal("0.000001414"))
    }

    @Test func followsTheCursorWhilePagesAreFull() async throws {
        let project = #"{"project_id":"p","periods":[{"consumption":[{"timeframe_start":"2026-11-02T00:00:00Z","metrics":[{"metric_name":"compute_unit_seconds","value":36}]}]}]}"#
        let full = "{\"projects\":[" + Array(repeating: project, count: 100).joined(separator: ",")
            + "],\"pagination\":{\"cursor\":\"next+cursor\"}}"
        let short = "{\"projects\":[" + project + "],\"pagination\":{\"cursor\":\"end\"}}"
        let http = MockHTTPClient { request in
            HTTPResponse(status: 200, json: request.query("cursor").isEmpty ? full : short)
        }
        let snapshot = try await NeonProvider(http: http).fetchSpend(FakeKeys.credentials(.neon), now: testNow)
        #expect(http.requests.count == 2)
        // The cursor goes back unchanged, plus sign included.
        #expect(http.requests[1].query("cursor") == ["next+cursor"])
        #expect(snapshot.usage.first { $0.id == "compute_unit_seconds" }?.value == decimal("1.01"))
    }

    @Test func forbiddenMeansThePlanLacksTheAPI() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: "{}") }
        do {
            _ = try await NeonProvider(http: http).fetchSpend(FakeKeys.credentials(.neon), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            guard case .planNotSupported = error else { Issue.record("Got \(error)"); return }
        } catch {
            Issue.record("Got \(error)")
        }
    }

    @Test func verifiesTheSpendingThreshold() async throws {
        let http = MockHTTPClient(routes: ["/billing/spending_limit": try json("neon-spending-limit.json")])
        let results = await NeonProvider(http: http).verifyCaps(FakeKeys.credentials(.neon), now: testNow)
        #expect(http.requests.first?.path == "/api/v2/organizations/org-cool-cloud-123/billing/spending_limit")
        #expect(results.first?.status == .on("Neon reports a spending threshold of $500.00 a month. It emails "
            + "admins; it doesn't stop usage."))

        let none = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"spending_limit_cents":null}"#) }
        let off = await NeonProvider(http: none).verifyCaps(FakeKeys.credentials(.neon), now: testNow)
        #expect(off.first?.status == .off("Neon reports no spending threshold."))
    }
}

@Suite struct SupabaseProviderTests {
    @Test func hasNoSpendAPI() async {
        let provider = SupabaseProvider()
        #expect(ProviderID.supabase.info.capability == .noUsageAPI)
        #expect(!ProviderID.supabase.info.connects)
        await #expect(throws: SpendError.noUsageAPI) {
            try await provider.fetchSpend(ProviderCredentials(provider: .supabase, values: [:]), now: testNow)
        }
    }
}

// swiftlint:enable line_length
