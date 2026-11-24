import Foundation
@testable import KillCordCore
import Testing

@Suite struct ConnectionRegistryTests {
    /// Hands out fixed ids in order, so tests can name them.
    final class IDs {
        private var next = 0
        func make() -> UUID {
            next += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", next))!
        }
    }

    @Test func secondConnectionOfAProviderGetsANumberedNameAndItsOwnID() {
        var registry = ConnectionRegistry()
        let ids = IDs()
        let first = registry.add(.anthropic, now: testNow, makeID: ids.make)
        let second = registry.add(.anthropic, now: testNow.addingTimeInterval(1), makeID: ids.make)
        registry.add(.openai, now: testNow, makeID: ids.make)
        #expect(first.name == "Anthropic")
        #expect(second.name == "Anthropic 2")
        #expect(first.id != second.id)
        #expect(registry.records(for: .anthropic).map(\.id) == [first.id, second.id])
        #expect(registry.providers == [.anthropic, .openai])
        #expect(registry.add(.anthropic, now: testNow, makeID: ids.make).name == "Anthropic 3")
    }

    @Test func renamesTrimsAndFallsBackToTheDefault() {
        var registry = ConnectionRegistry()
        let first = registry.add(.anthropic, now: testNow)
        let second = registry.add(.anthropic, now: testNow.addingTimeInterval(1))
        registry.rename(second.id, to: "  Client work \n")
        #expect(registry.record(second.id)?.name == "Client work")
        registry.rename(first.id, to: "Personal")
        // Back to the default: "Anthropic" is free again.
        registry.rename(second.id, to: "   ")
        #expect(registry.record(second.id)?.name == "Anthropic")
        #expect(registry.names == [first.id: "Personal", second.id: "Anthropic"])
    }

    @Test func reconcileDropsOnlyRecordsWhoseItemIsSurelyGone() {
        var registry = oneEach([.anthropic, .neon, .openai])
        struct Locked: Error {}
        let changed = registry.reconcile { record in
            switch record.provider {
            case .neon: return false
            case .openai: throw Locked()
            default: return true
            }
        }
        #expect(changed)
        #expect(registry.records.map(\.provider) == [.anthropic, .openai])
    }

    @Test func readsAVersionOneRegistryKeepingItsIDs() throws {
        // What Kill Cord 0.1.2 saved: no names, version 1.
        let versionOne = """
        {"version":1,"records":[{"id":"\(UUID.of(.openai).uuidString)","provider":"openai","createdAt":0}]}
        """
        let decoded = try JSONDecoder().decode(ConnectionRegistry.self, from: Data(versionOne.utf8))
        #expect(decoded.version == 1)
        #expect(decoded.records == [ConnectionRecord(id: .of(.openai), provider: .openai,
                                                     createdAt: Date(timeIntervalSinceReferenceDate: 0))])
        #expect(decoded.records.first?.name == "OpenAI")
        #expect(ConnectionRegistry(records: decoded.records).version == 2)
    }

    @Test func roundTripsThroughJSON() throws {
        var registry = oneEach([.google, .twilio])
        registry.add(.google, now: testNow)
        let data = try JSONEncoder().encode(registry)
        #expect(try JSONDecoder().decode(ConnectionRegistry.self, from: data) == registry)
        #expect(registry.version == ConnectionRegistry.currentVersion)
    }

    /// The Keychain payload is a JSON object keyed by these field ids. A later migration (and anything that
    /// reads the items) depends on them, so renaming one needs a migration, not just a code change.
    @Test func credentialFieldIDsAreStable() { // swiftlint:disable:this function_body_length
        let fields = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, $0.info.fields.map(\.id)) })
        #expect(fields == [
            .anthropic: ["apiKey"],
            .google: ["serviceAccountJSON", "exportTable", "billingAccountID"],
            .openai: ["apiKey"],
            .vercel: ["token", "teamID"],
            .cloudflare: ["token", "accountID"],
            .twilio: ["accountSID", "apiKeySID", "secret"],
            .neon: ["apiKey", "orgID"],
            .supabase: [],
            .runpod: ["apiKey"],
            .deepinfra: ["apiKey"],
            .xapi: ["apiKey"],
            .bfl: ["apiKey"],
            .digitalocean: ["apiKey"],
            .telnyx: ["apiKey"],
            .luma: ["apiKey"],
            .heygen: ["apiKey"],
            .browseruse: ["apiKey"],
            .novita: ["apiKey"],
            .baseten: ["apiKey"],
            .hunter: ["apiKey"],
            .zerobounce: ["apiKey"],
            .vonage: ["apiKey", "apiSecret"],
            .plivo: ["authID", "authToken"],
            .openrouter: ["apiKey"],
            .dataforseo: ["login", "password"],
            .ahrefs: ["apiKey"],
            .firecrawl: ["apiKey"],
            .treg: ["token", "org"],
            .monid: ["apiKey"],
            .fal: ["apiKey"],
            .elevenlabs: ["apiKey"],
            .xai: ["managementKey", "teamID"],
            .deepseek: ["apiKey"],
            .apify: ["apiKey"],
            .tavily: ["apiKey"],
            .deepgram: ["apiKey", "projectID"],
            .runway: ["apiKey"],
            .serpapi: ["apiKey"],
            .brightdata: ["apiKey"],
            .scrapecreators: ["apiKey"],
            .stability: ["apiKey"],
            .moonshot: ["apiKey"],
            .exa: ["apiKey"],
            .scrapingbee: ["apiKey"],
            .scrapfly: ["apiKey"],
            .kie: ["apiKey"],
            .bland: ["apiKey"],
            .llamacloud: ["apiKey", "organizationID", "region"],
            .custom: ["serviceName", "url", "method", "authStyle", "authName", "authValue", "key", "key2", "body",
                      "remainingPath", "usedPath", "limitPath", "resetPath", "currencyPath", "unit", "scale",
                      "dollarsPerUnit", "kind", "pollMinutes", "costsMoney"],
            .manual: ["serviceName", "plan", "price", "period", "renewsOn", "allowance", "allowanceUnit", "remindDays"]
        ])
        #expect(Brand.keychainService == "app.killcord.KillCord.providers")
    }
}
