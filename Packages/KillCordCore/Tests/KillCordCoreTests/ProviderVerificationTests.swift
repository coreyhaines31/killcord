import Foundation
@testable import KillCordCore
import Testing

/// Providers that shipped in 0.3.1 were used with real accounts; everything added since is Beta until it's
/// confirmed with a live account. This list is the v0.3.1 tag's `ProviderID`, written out so a new adapter
/// can't be marked verified by accident.
@Suite struct ProviderVerificationTests {
    private let shippedIn031: Set<ProviderID> = [
        .anthropic, .google, .openai, .vercel, .cloudflare, .twilio, .neon, .supabase,
        .openrouter, .dataforseo, .ahrefs, .firecrawl, .treg, .monid
    ]

    @Test func everyProviderFrom031IsVerified() {
        for provider in shippedIn031 {
            #expect(provider.info.verification == .liveVerified, "\(provider.rawValue)")
            #expect(!provider.isBeta, "\(provider.rawValue)")
        }
    }

    @Test func everyProviderAddedSince031IsBeta() {
        let added = ProviderID.allCases.filter { !shippedIn031.contains($0) && $0 != .custom && $0 != .manual }
        #expect(!added.isEmpty)
        for provider in added {
            #expect(provider.info.verification == .beta, "\(provider.rawValue) must ship labeled Beta")
            #expect(provider.isBeta, "\(provider.rawValue)")
        }
    }

    @Test func customAndManualKeepTheirOwnLabels() {
        #expect(ProviderID.custom.info.verification == .notApplicable)
        #expect(ProviderID.manual.info.verification == .notApplicable)
        #expect(!ProviderID.custom.isBeta)
        #expect(!ProviderID.manual.isBeta)
    }

    @Test func theWordsArePlain() {
        #expect(ProviderVerification.betaDetail
            == "Not yet verified with a live account. Numbers come from the provider's documented API.")
        #expect(ProviderVerification.issuesURL.absoluteString == "https://github.com/coreyhaines31/killcord/issues")
        for text in [ProviderVerification.betaLabel, ProviderVerification.betaDetail, ProviderVerification.betaErrorLine] {
            #expect(!text.contains("\u{2014}"), "No em dashes in user-facing copy")
        }
    }
}
