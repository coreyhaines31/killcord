import Foundation

/// Settings copy for the services in `ProviderInfo.batch3Providers`, kept apart so `ProviderGuide.swift` stays
/// readable. `ProviderGuide.swift` routes each of these providers here.
extension ProviderInfo {
    var batch3ConsoleName: String {
        switch id {
        case .stability: "Stability AI platform"
        default: "service's site"
        }
    }

    /// None of these providers says how far behind its numbers run yet.
    var batch3DelaySummary: String? {
        switch id {
        case .stability: nil
        default: nil
        }
    }

    var batch3Requirement: String? {
        switch id {
        default: nil
        }
    }

    var batch3KeyPowerSummary: String? {
        switch id {
        case .stability: "Stability AI has no read-only key. This key can run generations on your credits."
        default: nil
        }
    }

    var batch3SetupSteps: [SetupStep] {
        func open(_ title: String) -> (String, URL)? { keyURL.map { (title, $0) } }
        switch id {
        case .stability:
            return [
                SetupStep("Open API Keys on the Stability AI platform", "Sign in at platform.stability.ai.",
                          link: open("Open Stability Keys")),
                SetupStep("Create a key just for Kill Cord and copy it", "Stability AI keys have no scopes, so "
                    + "revoke it there if it leaks.")
            ]
        default:
            return []
        }
    }
}
