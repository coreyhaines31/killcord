import Foundation
@testable import KillCordCore
import Testing

// Kill Cord Teams in the Mac app (unit 12 groundwork). The first suite is the promise to free users: with
// the flag off (the default), nothing Teams-related is constructed or contacted.

private let fakeToken = "kcd_TEST-mac-device-token-0123456789abcdef"
private let workspaceA = "11111111-1111-4111-8111-111111111111"
private let personal = "22222222-2222-4222-8222-222222222222"

private func freshDefaults() -> UserDefaults {
    let name = "app.killcord.tests.teams.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// The Teams host (default or local override), or any of the device API's paths. Plain "/api/v1" alone
/// isn't Teams: OpenRouter's own API lives there.
private func isTeamsRequest(_ request: HTTPRequest) -> Bool {
    let path = request.url.path
    return request.url.host == TeamsSettings.defaultBaseURL.host || request.url.host == "localhost"
        || ["/api/v1/devices", "/api/v1/me", "/api/v1/orgs"].contains { path.hasPrefix($0) }
}

@Suite struct TeamsFlagOffTests {
    @Test func theFlagDefaultsToOff() {
        let settings = TeamsSettings.load(from: freshDefaults())
        #expect(settings.isEnabled == false)
        #expect(settings.baseURL == TeamsSettings.defaultBaseURL)
    }

    @MainActor
    @Test func withTheFlagOffNoSessionIsBuiltAndAFullRefreshNeverContactsTeams() async throws {
        let defaults = freshDefaults()
        defaults.set("http://localhost:3000", forKey: TeamsSettings.baseURLKey)
        let token = try json("google-token.json")
        let http = MockHTTPClient { request in
            request.url.host == "oauth2.googleapis.com" ? token : HTTPResponse(status: 503)
        }
        // What the app builds at launch: every provider adapter, and Teams only if the flag allows.
        let session = TeamsSession.makeIfEnabled(defaults: defaults, http: http, store: InMemorySecretStore())
        #expect(session == nil)
        for provider in ProviderID.allCases where provider.info.connects && provider != .manual {
            let adapter: SpendProvider = provider == .google
                ? GoogleCloudProvider(http: http, signer: FakeSigner())
                : SpendProviders.make(provider, http: http)
            _ = try? await adapter.fetchSpend(FakeKeys.credentials(provider), now: Date())
        }
        #expect(Set(http.requests.compactMap(\.url.host)).count >= 8, "the refresh cycle should have asked the providers")
        #expect(http.requests.filter(isTeamsRequest).isEmpty)
    }

    @MainActor
    @Test func aSessionRefusesToSignInWhenTheFlagIsOff() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: "{}") }
        let client = TeamsClient(baseURL: TeamsSettings.defaultBaseURL, http: http,
                                 tokens: TeamsTokenStore(store: InMemorySecretStore()))
        let session = TeamsSession(settings: TeamsSettings(isEnabled: false), client: client, defaults: freshDefaults())
        await session.signIn(deviceName: "Test Mac")
        #expect(session.state == .failed(.disabled))
        #expect(http.requests.isEmpty)
    }
}

@Suite struct TeamsSettingsTests {
    @Test(arguments: [
        ("https://app.killcord.app", true), ("https://staging.example.test", true), ("http://localhost:3000", true),
        ("http://127.0.0.1:3000", true), ("http://example.com", false), ("ftp://localhost", false),
        ("https://user:pass@app.killcord.app", false), ("https://app.killcord.app/evil?x=1", false)
    ])
    func baseURLOverride(_ text: String, _ allowed: Bool) {
        #expect((TeamsSettings.validBaseURL(text) != nil) == allowed)
    }

    @Test func theFlagCanBeTurnedOnOnlyThroughDefaults() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: TeamsSettings.enabledKey)
        defaults.set("http://example.com", forKey: TeamsSettings.baseURLKey)
        let settings = TeamsSettings.load(from: defaults)
        #expect(settings.isEnabled)
        #expect(settings.baseURL == TeamsSettings.defaultBaseURL, "an unsafe override is ignored")
    }

    @Test func theTokenAccountCanNeverBeAConnectionsAccount() {
        #expect(UUID(uuidString: TeamsTokenStore.account) == nil)
    }
}

/// A scripted cloud that follows the killcord-cloud device API contract (PR #30).
private final class FakeCloud: @unchecked Sendable {
    var tokenAnswers: [HTTPResponse]
    let lock = NSLock()

    init(tokenAnswers: [HTTPResponse]) {
        self.tokenAnswers = tokenAnswers
    }

    static let start = HTTPResponse(status: 200, json: """
        {"device_code":"dev-code-TEST","user_code":"BCDF-GHJK","verification_uri":"http://localhost:3000/device",
         "verification_uri_complete":"http://localhost:3000/device?code=BCDF-GHJK","expires_in":600,"interval":5}
        """)
    static let pending = HTTPResponse(status: 400, json: #"{"error":"authorization_pending"}"#)
    static let token = HTTPResponse(status: 200, json: #"{"access_token":"\#(fakeToken)","token_type":"Bearer"}"#)
    static let account = HTTPResponse(status: 200, json: """
        {"email":"mia@example.test","workspaces":[
          {"id":"\(personal)","name":"Personal","role":"owner","personal":true},
          {"id":"\(workspaceA)","name":"Acme","role":"member","personal":false}]}
        """)
    static let spend = HTTPResponse(status: 200, json: """
        {"month":"2026-11","total":"14.75000001","units":[
          {"label":"mia-laptop","how":"assigned","amount":"14.75000000"},
          {"label":"max","how":"reported","amount":"0.00000001"}]}
        """)

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        switch request.url.path {
        case "/api/v1/devices/start": return Self.start
        case "/api/v1/devices/token":
            return lock.withLock { tokenAnswers.isEmpty ? Self.pending : tokenAnswers.removeFirst() }
        case "/api/v1/me": return Self.account
        case "/api/v1/orgs/\(workspaceA)/me/spend": return Self.spend
        case "/api/v1/devices/current": return HTTPResponse(status: 204)
        default: return HTTPResponse(status: 404, json: #"{"error":"not_found"}"#)
        }
    }
}

@MainActor
private func makeSession(_ cloud: FakeCloud, store: InMemorySecretStore = InMemorySecretStore(),
                         defaults: UserDefaults = freshDefaults()) -> (TeamsSession, MockHTTPClient) {
    let http = MockHTTPClient { cloud.handle($0) }
    let settings = TeamsSettings(isEnabled: true, baseURL: URL(string: "http://localhost:3000")!)
    let client = TeamsClient(baseURL: settings.baseURL, http: http, tokens: TeamsTokenStore(store: store))
    let session = TeamsSession(settings: settings, client: client, defaults: defaults, sleep: { _ in })
    return (session, http)
}

@Suite @MainActor struct TeamsSignInTests {
    @Test func pendingThenApprovedSignsInAndPicksTheTeamWorkspace() async throws {
        let store = InMemorySecretStore()
        let cloud = FakeCloud(tokenAnswers: [FakeCloud.pending, FakeCloud.pending, FakeCloud.token])
        let (session, http) = makeSession(cloud, store: store)
        await session.signIn(deviceName: "Mia's MacBook")
        guard case .signedIn(let account) = session.state else { Issue.record("not signed in: \(session.state)"); return }
        #expect(account.email == "mia@example.test")
        #expect(session.selectedWorkspaceID == workspaceA, "a team workspace is preferred over Personal")
        #expect(TeamsTokenStore(store: store).read() == fakeToken)
        #expect(http.requests.filter { $0.path == "/api/v1/devices/token" }.count == 3)
        // The token only ever travels in the Authorization header.
        for request in http.requests {
            #expect(!request.url.absoluteString.contains(fakeToken))
        }
        let meRequest = try #require(http.requests.first { $0.path == "/api/v1/me" })
        #expect(meRequest.headers["authorization"] == "Bearer " + fakeToken)
        #expect(meRequest.method == .get)
    }

    @Test func aDeniedSignInSaysSoAndStoresNothing() async {
        let store = InMemorySecretStore()
        let denied = HTTPResponse(status: 400, json: #"{"error":"access_denied"}"#)
        let (session, _) = makeSession(FakeCloud(tokenAnswers: [denied]), store: store)
        await session.signIn(deviceName: "Mac")
        #expect(session.state == .failed(.accessDenied))
        #expect(store.accounts.isEmpty)
    }

    @Test func anExpiredCodeSaysSo() async {
        let expired = HTTPResponse(status: 400, json: #"{"error":"expired_token"}"#)
        let (session, _) = makeSession(FakeCloud(tokenAnswers: [expired]))
        await session.signIn(deviceName: "Mac")
        #expect(session.state == .failed(.expired))
    }

    @Test func theCodeRunsOutIfNobodyApproves() async {
        let cloud = FakeCloud(tokenAnswers: [])
        let http = MockHTTPClient { cloud.handle($0) }
        let settings = TeamsSettings(isEnabled: true, baseURL: URL(string: "http://localhost:3000")!)
        let client = TeamsClient(baseURL: settings.baseURL, http: http,
                                 tokens: TeamsTokenStore(store: InMemorySecretStore()))
        let clock = TestClock()
        let session = TeamsSession(settings: settings, client: client, defaults: freshDefaults(),
                                   sleep: { seconds in clock.advance(seconds) }, now: { clock.now })
        await session.signIn(deviceName: "Mac")
        #expect(session.state == .failed(.expired))
        // Respects the 5-second interval over the 600-second life of the code.
        #expect(http.requests.filter { $0.path == "/api/v1/devices/token" }.count == 120)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

@Suite @MainActor struct TeamsSpendTests {
    @Test func mySpendIsExactDecimal() async throws {
        let (session, http) = makeSession(FakeCloud(tokenAnswers: [FakeCloud.token]))
        await session.signIn(deviceName: "Mac")
        #expect(await session.loadSpend(month: "2026-11") == nil)
        let spend = try #require(session.spend)
        #expect(spend.total == Decimal(string: "14.75000001", locale: Locale(identifier: "en_US_POSIX")))
        #expect(spend.units.map(\.how) == [.assigned, .reported])
        #expect(spend.units[1].amount == Decimal(string: "0.00000001", locale: Locale(identifier: "en_US_POSIX")))
        let request = try #require(http.requests.last)
        #expect(request.query("month") == ["2026-11"])
    }

    @Test func choosingAWorkspaceIsRememberedAndAnotherOrgsSpendIsRefusedQuietly() async {
        let defaults = freshDefaults()
        let (session, _) = makeSession(FakeCloud(tokenAnswers: [FakeCloud.token]), defaults: defaults)
        await session.signIn(deviceName: "Mac")
        session.select(workspaceID: personal)
        #expect(defaults.string(forKey: TeamsSettings.selectedWorkspaceKey) == personal)
        session.select(workspaceID: "33333333-3333-4333-8333-333333333333")
        #expect(session.selectedWorkspaceID == personal, "a workspace the server didn't list can't be chosen")
        #expect(await session.loadSpend() == .notFound)
    }

    @Test func signOutRevokesOnTheServerWithTheBearerTokenAndForgetsIt() async throws {
        let store = InMemorySecretStore()
        let (session, http) = makeSession(FakeCloud(tokenAnswers: [FakeCloud.token]), store: store)
        await session.signIn(deviceName: "Mac")
        await session.signOut()
        let request = try #require(http.requests.last)
        #expect(request.method == .delete)
        #expect(request.path == "/api/v1/devices/current")
        #expect(request.headers["authorization"] == "Bearer " + fakeToken)
        #expect(store.accounts.isEmpty)
        #expect(session.state == .signedOut)
    }

    @Test func signOutForgetsTheTokenEvenWhenTheServerIsDown() async {
        let store = InMemorySecretStore()
        try? TeamsTokenStore(store: store).save(fakeToken)
        let client = TeamsClient(baseURL: URL(string: "http://localhost:3000")!,
                                 http: MockHTTPClient { _ in throw URLError(.notConnectedToInternet) },
                                 tokens: TeamsTokenStore(store: store))
        await client.signOut()
        #expect(store.accounts.isEmpty)
    }
}

@Suite struct TeamsTokenSafetyTests {
    @Test func errorsNeverContainTheToken() async {
        let store = InMemorySecretStore()
        try? TeamsTokenStore(store: store).save(fakeToken)
        let echo = #"{"error":"bad token \#(fakeToken)","access_token":""}"#
        for status in [400, 401, 403, 404, 429, 500, 502, 200] {
            let http = MockHTTPClient { _ in HTTPResponse(status: status, json: echo, headers: ["X-Echo": fakeToken]) }
            let client = TeamsClient(baseURL: URL(string: "http://localhost:3000")!, http: http,
                                     tokens: TeamsTokenStore(store: store))
            var errors: [Error] = []
            do { _ = try await client.me() } catch { errors.append(error) }
            do { _ = try await client.mySpend(workspaceID: workspaceA) } catch { errors.append(error) }
            do { _ = try await client.pollToken(deviceCode: "x") } catch { errors.append(error) }
            do { _ = try await client.startSignIn(deviceName: "Mac") } catch { errors.append(error) }
            #expect(!errors.isEmpty)
            for error in errors {
                #expect(!String(describing: error).contains(fakeToken))
                #expect(!error.localizedDescription.contains(fakeToken))
            }
        }
    }
}
