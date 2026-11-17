import Foundation
@testable import KillCordCore
import Testing

/// Keys must never show up in error text, descriptions, or anything else the app could display or log.
@Suite struct SecretSafetyTests {
    static let connectable = ProviderID.allCases.filter(\.info.connects)

    /// Responses a provider might send, including ones that echo the key back in the body.
    static func hostileResponses(echo secret: String) -> [HTTPResponse] {
        let echo = #"{"error":{"message":"invalid key \#(secret)"}}"#
        return [401, 403, 404, 429, 500, 502, 200].map { status in
            HTTPResponse(status: status, json: status == 200 ? #"{"unexpected": "\#(secret)"}"# : echo,
                         headers: ["Retry-After": "12", "X-Echo": secret])
        }
    }

    func assertClean(_ text: String, _ context: String) {
        for secret in FakeKeys.all {
            #expect(!text.contains(secret), "\(context) leaked a secret: \(text)")
        }
    }

    @Test(arguments: connectable)
    func errorsNeverContainTheKey(_ provider: ProviderID) async throws {
        let credentials = FakeKeys.credentials(provider)
        for response in Self.hostileResponses(echo: credentials.secrets.first ?? "none") {
            let token = try json("google-token.json")
            let http = MockHTTPClient { request in
                request.url.host == "oauth2.googleapis.com" ? token : response
            }
            let adapter: SpendProvider = provider == .google
                ? GoogleCloudProvider(http: http, signer: FakeSigner())
                : SpendProviders.make(provider, http: http)
            do {
                _ = try await adapter.fetchSpend(credentials, now: testNow)
                Issue.record("\(provider) accepted a hostile \(response.status) response")
            } catch {
                assertClean(String(describing: error), "\(provider) description")
                assertClean(error.localizedDescription, "\(provider) localizedDescription")
                if let spend = error as? SpendError {
                    assertClean(spend.message(for: provider), "\(provider) message")
                    assertClean(spend.shortLabel, "\(provider) label")
                    let encoded = String(data: try JSONEncoder().encode(spend), encoding: .utf8) ?? ""
                    assertClean(encoded, "\(provider) saved error")
                }
            }
            _ = await adapter.verifyCaps(credentials, now: testNow)
        }
    }

    @Test func networkFailuresDoNotCarryTheURLOrKey() async {
        let http = MockHTTPClient { _ in throw URLError(.timedOut) }
        do {
            _ = try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: testNow)
        } catch {
            #expect(error as? SpendError == .network)
        }
        #expect(SpendError(urlError: URLError(.notConnectedToInternet)) == .offline)
    }

    @Test(arguments: ProviderID.allCases)
    func everyMessageIsFreeOfSecrets(_ provider: ProviderID) {
        let errors: [SpendError] = [
            .notConfigured, .invalidKey, .missingScope(hint: "Add Billing Read."), .rateLimited(retryAfter: 90),
            .rateLimited(retryAfter: nil), .noUsageAPI, .requiresSetup("export"), .planNotSupported("Upgrade."),
            .offline, .network, .server(status: 503), .unexpectedStatus(409), .unexpectedResponse
        ]
        for error in errors {
            assertClean(error.message(for: provider), "message")
            #expect(!error.message(for: provider).contains("—"))
        }
    }

    @Test(arguments: connectable)
    func credentialsNeverPrintTheirValues(_ provider: ProviderID) {
        let credentials = FakeKeys.credentials(provider)
        assertClean(credentials.description, "description")
        assertClean(credentials.debugDescription, "debugDescription")
        assertClean(String(describing: credentials), "String(describing:)")
        assertClean("\(credentials)", "interpolation")
        var dumped = ""
        dump(credentials, to: &dumped)
        assertClean(dumped, "dump")
        #expect(!credentials.secrets.isEmpty)
    }

    @Test func redactorScrubsKnownSecrets() {
        let text = "failed with \(FakeKeys.openai) and \(FakeKeys.anthropic)"
        let clean = Redactor.redact(text, secrets: [FakeKeys.openai, FakeKeys.anthropic])
        #expect(clean == "failed with <redacted> and <redacted>")
        #expect(Redactor.redact("abc", secrets: ["ab"]) == "abc")
    }
}

@Suite struct CredentialStoreTests {
    @Test func roundTripsThroughTheSecretStore() throws {
        let secrets = InMemorySecretStore()
        let store = CredentialStore(secrets: secrets)
        #expect(try store.load(.anthropic) == nil)
        try store.save(FakeKeys.credentials(.anthropic))
        try store.save(FakeKeys.credentials(.twilio))
        #expect(try store.load(.anthropic)?["apiKey"] == FakeKeys.anthropic)
        #expect(store.connected() == [.anthropic, .twilio])
        #expect(secrets.accounts == ["anthropic", "twilio"])
        try store.delete(.anthropic)
        #expect(try store.load(.anthropic) == nil)
        #expect(store.connected() == [.twilio])
    }

    @Test func keepsOnlyKnownFieldsAndTrimsWhitespace() throws {
        let store = CredentialStore(secrets: InMemorySecretStore())
        try store.save(ProviderCredentials(provider: .openai, values: ["apiKey": "  \(FakeKeys.openai)\n", "junk": "x"]))
        let loaded = try #require(try store.load(.openai))
        #expect(loaded["apiKey"] == FakeKeys.openai)
        #expect(loaded["junk"] == nil)
    }

    @Test func reportsMissingRequiredFields() {
        let partial = ProviderCredentials(provider: .cloudflare, values: ["token": "t", "accountID": " "])
        #expect(partial.missingFields.map(\.id) == ["accountID"])
        let optionalLeftOut = ProviderCredentials(provider: .vercel, values: ["token": "t"])
        #expect(optionalLeftOut.missingFields.isEmpty)
    }
}
