import Foundation
@testable import KillCordCore
import Testing

@Suite struct ProviderGuideTests {
    @Test func keyKindReadsAsASentence() {
        #expect(ProviderID.anthropic.info.keyKindInSentence
            == "an admin API key, or a service account or personal key that isn't scoped to a workspace")
        #expect(ProviderID.cloudflare.info.keyKindInSentence == "an API token with Billing Read")
        #expect(ProviderID.google.info.keyKindInSentence.hasPrefix("a service account key"))
        #expect(SpendError.invalidKey.message(for: .anthropic)
            == "Anthropic rejected the key. It may be revoked, expired, or the wrong kind: Kill Cord needs "
            + "an admin API key, or a service account or personal key that isn't scoped to a workspace.")
    }

    /// The cost report needs an organization and a key that isn't scoped to a workspace (Anthropic's Admin
    /// API docs, checked 2026-11-17). Admin, personal, and service account keys all work.
    @Test func anthropicSetupStartsWithTheOrganizationAndAcceptsIdentityKeys() throws {
        let steps = ProviderID.anthropic.info.setupSteps
        let first = try #require(steps.first)
        #expect(first.detail.contains("Individual Org"))
        #expect(first.link?.url.absoluteString == "https://platform.claude.com/settings/organization")
        #expect(steps.contains { $0.title.contains("service account") && $0.title.contains("recommended") })
        let text = steps.map { $0.title + " " + $0.detail }.joined(separator: " ")
        #expect(text.contains("isn't scoped to a workspace"))
        #expect(text.contains("Admin API key"))
        #expect(!text.localizedCaseInsensitiveContains("regular API key"))
        #expect(ProviderID.anthropic.info.fields.first?.placeholder == "sk-ant-…")
        // No claim about which role is enough: the docs don't say.
        let warning = try #require(ProviderID.anthropic.info.keyPowerWarning)
        #expect(warning.contains("same permissions as the account it's linked to"))
        #expect(ProviderID.anthropic.keyPower == .canManage)
    }

    @Test func anthropicKeyProblemsNameTheOrganizationAndWorkspaceCauses() {
        for error in [SpendError.invalidKey, .missingScope(hint: "")] {
            let fix = error.fix(for: .anthropic) ?? ""
            #expect(fix.contains("Individual Org"))
            #expect(fix.contains("isn't scoped to a workspace"))
        }
        #expect(SpendError.invalidKey.fix(for: .openai)?.contains("Individual Org") == false)
    }

    @Test func everyConnectingProviderHasStepsWithAnOpenButtonFirst() throws {
        for provider in ProviderID.allCases where provider.info.connects {
            let steps = provider.info.setupSteps
            #expect(steps.count >= 2, "\(provider)")
            let link = try #require(steps.first?.link, "\(provider)")
            #expect(link.url.scheme == "https")
            #expect(link.title.hasPrefix("Open "))
        }
        #expect(ProviderID.supabase.info.setupSteps.isEmpty)
    }

    @Test func stepLinksComeFromTheProviderFacts() {
        // A wrong link is worse than none: the open buttons reuse the documented key pages.
        // Google and Anthropic have a setup step first; their key page is the last step.
        let keyLast: Set<ProviderID> = [.google, .anthropic]
        for provider in ProviderID.allCases where provider.info.connects && !keyLast.contains(provider) {
            #expect(provider.info.setupSteps.first?.link?.url == provider.info.keyURL, "\(provider)")
        }
        for provider in keyLast {
            #expect(provider.info.setupSteps.last?.link?.url == provider.info.keyURL, "\(provider)")
        }
    }

    @Test func settingsCopyHasNoEmDashes() {
        var text: [String] = []
        for provider in ProviderID.allCases {
            let info = provider.info
            text += [info.overview, info.capabilityLabel, info.consoleName, info.keyKindInSentence]
            text += [info.keyPowerSummary, info.keyPowerWarning, info.lag.note].compactMap { $0 }
            text += info.setupSteps.flatMap { [$0.title, $0.detail, $0.link?.title ?? ""] }
            text += info.fields.flatMap { [$0.label, $0.help, $0.placeholder] }
            for error in [SpendError.invalidKey, .offline, .notConfigured, .rateLimited(retryAfter: nil)] {
                text += [error.message(for: provider), error.fix(for: provider) ?? ""]
            }
        }
        for line in text {
            #expect(!line.contains("\u{2014}"), "em dash in: \(line)")
        }
    }

    @Test func keyPowerSummaryExistsWheneverThereIsAWarning() {
        for provider in ProviderID.allCases {
            #expect((provider.info.keyPowerSummary == nil) == (provider.info.keyPowerWarning == nil), "\(provider)")
        }
    }
}
