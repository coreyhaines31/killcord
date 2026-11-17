import Foundation
@testable import KillCordCore
import Testing

@Suite struct ProviderGuideTests {
    @Test func keyKindReadsAsASentence() {
        #expect(ProviderID.anthropic.info.keyKindInSentence == "an admin API key")
        #expect(ProviderID.cloudflare.info.keyKindInSentence == "an API token with Billing Read")
        #expect(ProviderID.google.info.keyKindInSentence.hasPrefix("a service account key"))
        #expect(SpendError.invalidKey.message(for: .anthropic)
            == "Anthropic rejected the key. It may be revoked, expired, or the wrong kind: Kill Cord needs "
            + "an admin API key.")
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
        for provider in ProviderID.allCases where provider.info.connects && provider != .google {
            #expect(provider.info.setupSteps.first?.link?.url == provider.info.keyURL, "\(provider)")
        }
        #expect(ProviderID.google.info.setupSteps.last?.link?.url == ProviderID.google.info.keyURL)
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
