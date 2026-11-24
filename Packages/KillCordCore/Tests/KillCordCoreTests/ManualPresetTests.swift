import Foundation
@testable import KillCordCore
import Testing

/// Presets for services with no billing API. Each link comes from the service's docs.
@Suite struct ManualPresetTests {
    @Test func coversTheServicesWithNoBillingAPI() {
        #expect(ManualPreset.corePresets.map(\.name) == [
            "AssemblyAI", "Cerebras", "Cohere", "E2B", "Gojiberry", "Groq", "Jina AI", "Modal", "Perplexity",
            "Pinecone", "Replicate", "Truelist", "Twelve Labs", "TypeSafe Jev", "Unstructured", "Voyage AI"
        ])
        #expect(ManualPreset.morePresets.map(\.name) == [
            "Apollo", "Brave Search API", "Clay", "Cloudinary", "Composio", "Enrich Layer", "Fly.io", "Gladia",
            "Hetzner", "Ideogram", "Instantly", "Lambda", "Leonardo.Ai", "Linode (Akamai Cloud)", "n8n Cloud",
            "Netlify", "People Data Labs", "Railway", "Render", "SambaNova Cloud", "Serper", "Vultr", "Zapier"
        ])
        // The picker lists every preset alphabetically.
        let names = ManualPreset.all.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(Set(ManualPreset.all.map(\.id)).count == ManualPreset.all.count)
    }

    @Test func matchesTheNameAnEntryWasGivenLoosely() {
        #expect(ManualPreset.matching("Groq")?.id == "groq")
        #expect(ManualPreset.matching("  twelve labs ")?.id == "twelvelabs")
        #expect(ManualPreset.matching("jina-ai")?.id == "jina")
        #expect(ManualPreset.matching("TypeSafe Jev")?.id == "typesafe")
        #expect(ManualPreset.matching("Acme Mail") == nil)
        #expect(ManualPreset.matching("truelist")?.id == "truelist")
        #expect(ManualPreset.matching("") == nil)
        #expect(ManualPreset.matching(nil) == nil)
    }

    @Test func everyLinkIsHTTPSAndEveryCapIsSelfReportedWithSteps() {
        let caps = ManualPreset.all.flatMap(\.caps)
        #expect(Set(caps.map(\.id)).count == caps.count)
        #expect(Set(caps.map(\.id)).isDisjoint(with: CapsCatalog.controls.map(\.id)))
        for preset in ManualPreset.all {
            #expect(preset.billingURL.scheme == "https" && preset.docURL.scheme == "https", "\(preset.id)")
            #expect(!preset.note.contains("\u{2014}"))
        }
        for cap in caps {
            #expect(cap.provider == .manual)
            #expect(cap.verification == .selfReported, "\(cap.id): there's no API to check it")
            #expect(cap.consoleURL.scheme == "https" && cap.docURL.scheme == "https")
            #expect(!cap.steps.isEmpty)
            for text in [cap.name, cap.summary, cap.caveat ?? ""] + cap.steps {
                #expect(!text.contains("\u{2014}"), "Em dash in \(cap.id)")
            }
        }
    }

    @Test func manualEntriesGetTheirPresetsCapsOnce() {
        #expect(CapsCatalog.controls(for: .manual).isEmpty)
        let caps = CapsCatalog.controls(for: .manual, manualServices: ["Groq", "groq", "Acme Mail", "Cohere"])
        #expect(caps.map(\.id) == ["manual.groq.spend-limit", "manual.groq.spend-alerts"])
        #expect(CapsCatalog.controls(for: .openai, manualServices: ["Groq"]) == CapsCatalog.controls(for: .openai))
    }

    @Test func presetCapsCanBeMarkedAndComeDueForARecheck() throws {
        let cap = try #require(CapsCatalog.control("manual.groq.spend-limit"))
        var state = CapAuditState()
        #expect(state.progress(of: [cap], now: testNow) == .init(done: 0, total: 1, needsAttention: 1))
        state.mark(cap.id, .done(at: testNow))
        #expect(state.progress(of: [cap], now: testNow).isComplete)
        let later = testNow.addingTimeInterval(CapAuditState.recheckAfter + 1)
        #expect(state.dueForRecheck(now: later).map(\.id) == [cap.id])
    }
}
