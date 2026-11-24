import Foundation
@testable import KillCordCore
import Testing

/// The rules every spend or usage adapter in `ProviderInfo.batch3Providers` shares (balance ones are in
/// `BalanceProviderRulesTests`): https only, its documented host, a key-power label, and no network for a
/// missing key.
@Suite struct Batch3SpendRulesTests {
    static let providers: [ProviderID] = [
        .llamacloud,
        .cartesia,
        .together,
        .fireworks,
        .vapi,
        .retell,
        .browserbase,
        .resend,
        .postmark,
        .mistral,
        .huggingface
    ]
    static let hosts: [ProviderID: Set<String>] = [
        .llamacloud: ["api.cloud.llamaindex.ai", "api.cloud.eu.llamaindex.ai"],
        .cartesia: ["api.cartesia.ai"],
        .together: ["api.together.ai"],
        .fireworks: ["api.fireworks.ai"],
        .vapi: ["api.vapi.ai"],
        .retell: ["api.retellai.com"],
        .browserbase: ["api.browserbase.com"],
        .resend: ["api.resend.com"],
        .postmark: ["api.postmarkapp.com"],
        .mistral: ["api.mistral.ai"],
        .huggingface: ["huggingface.co"]
    ]
    static let keyPowers: [ProviderID: KeyPower] = [
        .llamacloud: .canManage,
        .cartesia: .canManage,
        .vapi: .canManage,
        .retell: .readOnlyIfChosen,
        .resend: .canManage,
        .mistral: .canManage,
        .huggingface: .readOnlyIfChosen
    ]

    @Test(arguments: providers)
    func onlyCallsItsDocumentedHost(_ provider: ProviderID) async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 503) }
        _ = try? await SpendProviders.make(provider, http: http).fetchSpend(FakeKeys.credentials(provider), now: testNow)
        #expect(!http.requests.isEmpty)
        for request in http.requests {
            #expect(request.url.scheme == "https")
            #expect(Self.hosts[provider]?.contains(request.url.host ?? "") == true)
        }
    }

    @Test(arguments: providers)
    func aMissingKeyNeverReachesTheNetwork(_ provider: ProviderID) async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        await #expect(throws: SpendError.notConfigured) {
            try await SpendProviders.make(provider, http: http).fetchSpend(
                ProviderCredentials(provider: provider, values: [:]), now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test(arguments: providers)
    func setupSaysWhatTheKeyCanDo(_ provider: ProviderID) {
        let info = provider.info
        #expect(!info.capability.showsBalance)
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
