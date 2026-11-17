import Foundation
@testable import KillCordCore
import Testing

@Suite struct CredentialHintTests {
    @Test func secretsShowOnlyTheirLastFour() {
        let credentials = ProviderCredentials(provider: .anthropic, values: ["apiKey": FakeKeys.anthropic])
        let hints = credentials.hints
        #expect(hints.map(\.text) == ["Ending in 0001"])
        #expect(!hints.contains { $0.text.contains("sk-ant") })
    }

    @Test func shortSecretsShowNothing() {
        let credentials = ProviderCredentials(provider: .anthropic, values: ["apiKey": "sk-short"])
        #expect(credentials.hints.map(\.text) == ["Saved"])
    }

    @Test func serviceAccountShowsItsEmailAndNonSecretsShowAsIs() {
        let credentials = ProviderCredentials(provider: .google, values: [
            "serviceAccountJSON": FakeKeys.googleJSON, "exportTable": "kc-billing.billing.export"
        ])
        #expect(credentials.hints.map(\.text)
            == ["kill-cord@kc-billing.iam.gserviceaccount.com", "kc-billing.billing.export"])
        #expect(!credentials.hints.contains { $0.text.contains("PRIVATE") })
    }
}

