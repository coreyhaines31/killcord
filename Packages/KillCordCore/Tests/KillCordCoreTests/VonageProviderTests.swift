// Fixtures follow Vonage's documented response: https://developer.vonage.com/en/api/account
import Foundation
@testable import KillCordCore
import Testing

@Suite struct VonageProviderTests {
    @Test func readsTheBalanceInEurosWithBasicAuth() async throws {
        let http = MockHTTPClient(routes: ["/account/get-balance": try json("vonage-get-balance.json")])
        let snapshot = try await VonageProvider(http: http).fetchSpend(FakeKeys.credentials(.vonage), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://rest.nexmo.com/account/get-balance")
        let basic = Data("a1b2c3d4:\(FakeKeys.vonage)".utf8).base64EncodedString()
        #expect(request.headers["Authorization"] == "Basic \(basic)")
        // EUR stays EUR: Kill Cord never converts it to dollars.
        #expect(snapshot.balance == Balance(remaining: decimal("10.28"), unit: .money(Currency("EUR"))))
    }

    @Test func autoReloadOffConfirmsTheCap() async throws {
        let http = MockHTTPClient(routes: ["/account/get-balance": try json("vonage-get-balance.json")])
        let caps = await VonageProvider(http: http).verifyCaps(FakeKeys.credentials(.vonage), now: testNow)
        #expect(caps.map(\.capID) == [VonageProvider.autoReloadCapID])
        guard case .on = caps.first?.status else {
            Issue.record("Expected on, got \(caps)")
            return
        }
    }

    @Test func autoReloadOnMeansItDoesNotStop() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"value":3.5,"autoReload":true}"#) }
        let caps = await VonageProvider(http: http).verifyCaps(FakeKeys.credentials(.vonage), now: testNow)
        guard case .off = caps.first?.status else {
            Issue.record("Expected off, got \(caps)")
            return
        }
    }

    @Test func aMissingSecretNeverReachesTheNetwork() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        await #expect(throws: SpendError.notConfigured) {
            try await VonageProvider(http: http).fetchSpend(
                ProviderCredentials(provider: .vonage, values: ["apiKey": "a1b2c3d4"]), now: testNow)
        }
        #expect(http.requests.isEmpty)
    }
}
