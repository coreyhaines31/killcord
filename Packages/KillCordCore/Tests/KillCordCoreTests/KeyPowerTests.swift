import Foundation
@testable import KillCordCore
import Testing

@Suite struct KeyPowerTests {
    @Test func everyConnectableProviderHasAKeyPower() {
        for provider in ProviderID.allCases {
            #expect((provider.keyPower == .noKey) == !provider.info.connects)
            // A key that can manage the organization always comes with a warning to show.
            if provider.keyPower == .canManage { #expect(provider.info.keyPowerWarning != nil) }
        }
        #expect(ProviderID.anthropic.keyPower == .canManage)
        #expect(ProviderID.cloudflare.keyPower == .readOnly)
    }
}
