// swiftlint:disable line_length
// Recorded-shape fixtures with fake data. Each test checks the one documented request and the balance read.
import Foundation
@testable import KillCordCore
import Testing

@Suite struct DataForSEOProviderTests {
    @Test func readsTheDepositLeftWithBasicAuth() async throws {
        let http = MockHTTPClient(routes: ["/v3/appendix/user_data": try json("dataforseo-user-data.json")])
        let snapshot = try await DataForSEOProvider(http: http).fetchSpend(FakeKeys.credentials(.dataforseo), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.dataforseo.com/v3/appendix/user_data")
        let basic = Data("kc-test@example.com:\(FakeKeys.dataforseo)".utf8).base64EncodedString()
        #expect(request.headers["Authorization"] == "Basic \(basic)")
        #expect(snapshot.balance == .usd(Decimal(string: "41.2537")!, kind: .prepaid, limit: 50))
        #expect(snapshot.today == nil && snapshot.month == nil)
    }

    @Test func aLoginErrorInsideA200IsARejectedKey() async {
        let body = #"{"status_code":40100,"status_message":"You are not authorized.","tasks":null}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.invalidKey) {
            try await DataForSEOProvider(http: http).fetchSpend(FakeKeys.credentials(.dataforseo), now: testNow)
        }
    }

    @Test func aTaskErrorIsAnUnexpectedResponse() async {
        let body = #"{"status_code":20000,"tasks":[{"status_code":50000,"result":null}]}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await DataForSEOProvider(http: http).fetchSpend(FakeKeys.credentials(.dataforseo), now: testNow)
        }
    }
}

@Suite struct TregProviderTests {
    func client() throws -> MockHTTPClient {
        MockHTTPClient(routes: ["/auth/me": try json("treg-auth-me.json"), "/orgs/42/balance": try json("treg-balance.json")])
    }

    @Test func findsTheTeamThenReadsMicroDollarsExactly() async throws {
        let http = try client()
        let snapshot = try await TregProvider(http: http).fetchSpend(FakeKeys.credentials(.treg), now: testNow)
        #expect(http.requests.map(\.url.absoluteString) == ["https://treg.to/auth/me", "https://treg.to/orgs/42/balance"])
        #expect(http.requests.allSatisfy { $0.method == .get && $0.headers["X-Treg-Token"] == FakeKeys.treg })
        #expect(http.requests.allSatisfy { $0.headers["X-Treg-Org"] == nil })
        #expect(snapshot.balance == .usd(Decimal(string: "18.45")!))
        #expect(TregProvider.usd(1) == Decimal(string: "0.000001"))
    }

    @Test func aPersonalTokenSendsTheTeamSlug() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .treg, values: ["token": FakeKeys.treg, "org": "acme"])
        _ = try await TregProvider(http: http).fetchSpend(credentials, now: testNow)
        #expect(http.requests.allSatisfy { $0.headers["X-Treg-Org"] == "acme" })
    }

    @Test func aSlugThatCouldInjectAHeaderIsRefused() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .treg, values: ["token": FakeKeys.treg, "org": "acme\r\nX-Evil: 1"])
        await #expect(throws: SpendError.notConfigured) {
            try await TregProvider(http: http).fetchSpend(credentials, now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func noTeamChosenNeedsSetup() async throws {
        let http = MockHTTPClient(routes: ["/auth/me": HTTPResponse(status: 200, json: #"{"email":"a@example.com"}"#)])
        await #expect(throws: SpendError.requiresSetup("add your team's slug, or use a team token.")) {
            try await TregProvider(http: http).fetchSpend(FakeKeys.credentials(.treg), now: testNow)
        }
        #expect(http.requests.count == 1)
    }
}

@Suite struct MonidProviderTests {
    @Test func readsTheWallet() async throws {
        let http = MockHTTPClient(routes: ["/v1/wallet/balance": try json("monid-wallet-balance.json")])
        let snapshot = try await MonidProvider(http: http).fetchSpend(FakeKeys.credentials(.monid), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.monid.ai/v1/wallet/balance")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.monid)")
        #expect(snapshot.balance == .usd(Decimal(string: "27.35")!))
    }

    @Test func aNonCurrencyIsRefused() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"balance":{"value":1,"currency":"<b>x</b>"}}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await MonidProvider(http: http).fetchSpend(FakeKeys.credentials(.monid), now: testNow)
        }
    }

    @Test func showsMonidsOwnErrorMessage() async {
        let body = #"{"error":{"code":"UNAUTHORIZED","message":"Key revoked"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Key revoked")) {
            try await MonidProvider(http: http).fetchSpend(FakeKeys.credentials(.monid), now: testNow)
        }
    }
}

@Suite struct OpenRouterProviderTests {
    @Test func readsTheKeysLimitLeftAndItsSpend() async throws {
        let http = MockHTTPClient(routes: ["/api/v1/key": try json("openrouter-key.json")])
        let snapshot = try await OpenRouterProvider(http: http).fetchSpend(FakeKeys.credentials(.openrouter), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.url.absoluteString == "https://openrouter.ai/api/v1/key")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.openrouter)")
        #expect(snapshot.balance == .usd(Decimal(string: "7.75")!, kind: .prepaid, limit: 20))
        #expect(snapshot.today == usd("0.42"))
        #expect(snapshot.month == usd("9.6"))
    }

    @Test func aKeyWithNoLimitHasNoBalanceButStillHasSpend() async throws {
        let body = #"{"data":{"limit":null,"limit_remaining":null,"limit_reset":null,"usage":3,"usage_daily":1,"usage_weekly":2,"usage_monthly":3}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await OpenRouterProvider(http: http).fetchSpend(FakeKeys.credentials(.openrouter), now: testNow)
        #expect(snapshot.balance == nil)
        #expect(snapshot.today == usd("1"))
    }

    @Test func aResettingLimitIsAnAllowance() async throws {
        let body = #"{"data":{"limit":50,"limit_remaining":40,"limit_reset":"monthly","usage":10,"usage_daily":1,"usage_weekly":2,"usage_monthly":10}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await OpenRouterProvider(http: http).fetchSpend(FakeKeys.credentials(.openrouter), now: testNow)
        #expect(snapshot.balance?.kind == .allowance)
    }

    @Test func itsSpendCountsTowardTotals() {
        #expect(ProviderID.openrouter.info.capability.countsToday)
        #expect(ProviderID.openrouter.info.capability.countsMonth)
    }
}

@Suite struct FirecrawlProviderTests {
    @Test func readsCreditsLeftAndTheReset() async throws {
        let http = MockHTTPClient(routes: ["/v2/team/credit-usage": try json("firecrawl-credit-usage.json")])
        let snapshot = try await FirecrawlProvider(http: http).fetchSpend(FakeKeys.credentials(.firecrawl), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.url.absoluteString == "https://api.firecrawl.dev/v2/team/credit-usage")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.firecrawl)")
        let balance = try #require(snapshot.balance)
        #expect(balance.remaining == 4250)
        #expect(balance.unit == .units("credits"))
        #expect(balance.kind == .allowance)
        // Remaining includes pay-as-you-go credits, so the plan size isn't a limit.
        #expect(balance.limit == nil)
        #expect(balance.resetsAt == ISO8601.date("2026-11-30T23:59:59Z"))
    }

    @Test func notSuccessfulIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"success":false,"error":"nope"}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await FirecrawlProvider(http: http).fetchSpend(FakeKeys.credentials(.firecrawl), now: testNow)
        }
    }

    @Test func showsFirecrawlsErrorString() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 404, json: #"{"success":false,"error":"Could not find credit usage information"}"#) }
        await #expect(throws: SpendError.rejected(status: 404, detail: "Could not find credit usage information")) {
            try await FirecrawlProvider(http: http).fetchSpend(FakeKeys.credentials(.firecrawl), now: testNow)
        }
    }
}

@Suite struct AhrefsProviderTests {
    @Test func readsTheWorkspaceUnitsLeft() async throws {
        let http = MockHTTPClient(routes: ["/v3/subscription-info/limits-and-usage": try json("ahrefs-limits-and-usage.json")])
        let snapshot = try await AhrefsProvider(http: http).fetchSpend(FakeKeys.credentials(.ahrefs), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.url.absoluteString == "https://api.ahrefs.com/v3/subscription-info/limits-and-usage")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.ahrefs)")
        let balance = try #require(snapshot.balance)
        #expect(balance.remaining == 376_550)
        #expect(balance.limit == 500_000)
        #expect(balance.used == 123_450)
        #expect(balance.unit == .units("API units"))
        #expect(balance.resetsAt == ISO8601.date("2026-12-01T00:00:00Z"))
    }

    @Test func unknownUsageIsNotZero() async throws {
        let body = #"{"limits_and_usage":{"units_limit_workspace":500000,"units_usage_workspace":null,"usage_reset_date":"2026-12-01"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await AhrefsProvider(http: http).fetchSpend(FakeKeys.credentials(.ahrefs), now: testNow)
        #expect(snapshot.balance == nil)
    }

    @Test func anUnlimitedWorkspaceHasNoBalance() async throws {
        let body = #"{"limits_and_usage":{"units_limit_workspace":null,"units_usage_workspace":10,"usage_reset_date":"2026-12-01"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await AhrefsProvider(http: http).fetchSpend(FakeKeys.credentials(.ahrefs), now: testNow)
        #expect(snapshot.balance == nil)
    }
}

/// What every new adapter shares: read-only setup copy, one host, a key-power label, and no network for a
/// missing key.
@Suite struct BalanceProviderRulesTests {
    /// Services in `ProviderInfo.moreBalanceProviders`, kept in their own lists so the two batches don't collide.
    static let moreProviders: [ProviderID] = [.runpod, .xapi, .bfl, .telnyx, .luma, .heygen, .browseruse]
    static let moreHosts: [ProviderID: String] = [
        .runpod: "api.runpod.io",
        .xapi: "api.x.com",
        .bfl: "api.bfl.ai",
        .telnyx: "api.telnyx.com",
        .luma: "agents.lumalabs.ai",
        .heygen: "api.heygen.com",
        .browseruse: "api.browser-use.com"
    ]
    static let moreKeyPowers: [ProviderID: KeyPower] = [
        .runpod: .readOnlyIfChosen,
        .telnyx: .canManage,
        .heygen: .readOnlyIfChosen
    ]
    /// Services in `ProviderInfo.batch3Providers` that read a balance with GETs.
    static let batch3Providers: [ProviderID] = [.stability, .moonshot, .exa, .scrapingbee, .scrapfly, .kie, .bland]
    static let batch3Hosts: [ProviderID: String] = [
        .bland: "api.bland.ai",
        .kie: "api.kie.ai",
        .scrapfly: "api.scrapfly.io",
        .scrapingbee: "app.scrapingbee.com",
        .exa: "admin-api.exa.ai",
        .moonshot: "api.moonshot.ai",
        .stability: "api.stability.ai"
    ]
    static let batch3KeyPowers: [ProviderID: KeyPower] = [.moonshot: .readOnlyIfChosen, .exa: .canManage, .bland: .readOnlyIfChosen]
    static let balanceProviders: [ProviderID] = [.openrouter, .dataforseo, .ahrefs, .firecrawl, .treg, .monid, .fal, .elevenlabs, .xai, .deepseek, .apify, .tavily, .deepgram, .runway, .serpapi, .brightdata, .scrapecreators] + moreProviders
        + batch3Providers
    static let hosts: [ProviderID: String] = [
        .openrouter: "openrouter.ai", .dataforseo: "api.dataforseo.com", .ahrefs: "api.ahrefs.com",
        .firecrawl: "api.firecrawl.dev", .treg: "treg.to", .monid: "api.monid.ai", .fal: "api.fal.ai",
        .elevenlabs: "api.elevenlabs.io",
        .xai: "management-api.x.ai",
        .deepseek: "api.deepseek.com",
        .apify: "api.apify.com",
        .tavily: "api.tavily.com",
        .deepgram: "api.deepgram.com",
        .runway: "api.dev.runwayml.com",
        .serpapi: "serpapi.com",
        .brightdata: "api.brightdata.com",
        .scrapecreators: "api.scrapecreators.com"
    ].merging(moreHosts) { $1 }.merging(batch3Hosts) { $1 }
    /// What each provider's docs say its key can do. Anything not listed can make paid calls.
    static let keyPowers: [ProviderID: KeyPower] = [.fal: .readOnlyIfChosen, .elevenlabs: .readOnlyIfChosen, .xai: .canManage, .apify: .canManage, .deepgram: .canManage, .brightdata: .canManage].merging(moreKeyPowers) { $1 }
        .merging(batch3KeyPowers) { $1 }

    @Test(arguments: balanceProviders)
    func onlyGETsToItsDocumentedHost(_ provider: ProviderID) async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 503) }
        _ = try? await SpendProviders.make(provider, http: http).fetchSpend(FakeKeys.credentials(provider), now: testNow)
        #expect(!http.requests.isEmpty)
        for request in http.requests {
            #expect(request.method == .get)
            #expect(request.url.scheme == "https")
            #expect(request.url.host == Self.hosts[provider])
            #expect(request.body == nil)
        }
    }

    @Test(arguments: balanceProviders)
    func aMissingKeyNeverReachesTheNetwork(_ provider: ProviderID) async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        await #expect(throws: SpendError.notConfigured) {
            try await SpendProviders.make(provider, http: http).fetchSpend(
                ProviderCredentials(provider: provider, values: [:]), now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test(arguments: balanceProviders)
    func setupSaysWhatTheKeyCanDo(_ provider: ProviderID) {
        let info = provider.info
        #expect(info.capability.showsBalance)
        #expect(provider.keyPower == Self.keyPowers[provider, default: .canSpend])
        #expect(info.keyPowerWarning != nil)
        #expect(info.keyPowerSummary != nil)
        #expect(!info.setupSteps.isEmpty)
        for text in [info.overview, info.keyPowerWarning ?? "", info.keyPowerSummary ?? "", info.lag.note]
            + info.setupSteps.flatMap({ [$0.title, $0.detail] }) + info.fields.map(\.help) {
            #expect(!text.contains("\u{2014}"), "Em dash in \(provider) copy: \(text)")
        }
    }
}
// swiftlint:enable line_length
