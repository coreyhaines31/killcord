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

    @Test func adoptsKeysSavedBeforeRecordsExisted() {
        var registry = ConnectionRegistry()
        let ids = IDs()
        let changed = registry.reconcile(connected: [.openai, .anthropic], now: testNow, makeID: ids.make)
        #expect(changed)
        #expect(registry.records.map(\.provider) == [.anthropic, .openai])
        #expect(registry.records.allSatisfy { $0.createdAt == testNow })
        #expect(Set(registry.records.map(\.id)).count == 2)
    }

    @Test func keepsIDsAcrossLaunchesAndKeyReplacement() {
        var registry = ConnectionRegistry()
        registry.reconcile(connected: [.anthropic], now: testNow)
        let id = registry.record(for: .anthropic)?.id
        let changed = registry.reconcile(connected: [.anthropic], now: testNow.addingTimeInterval(86400))
        #expect(!changed)
        #expect(registry.record(for: .anthropic)?.id == id)
        #expect(registry.record(for: .anthropic)?.createdAt == testNow)
    }

    @Test func dropsRecordsWhoseKeyIsGoneAndGivesAReconnectANewID() {
        var registry = ConnectionRegistry()
        registry.reconcile(connected: [.anthropic, .neon], now: testNow)
        let first = registry.record(for: .neon)?.id
        let dropped = registry.reconcile(connected: [.anthropic], now: testNow)
        #expect(dropped)
        #expect(registry.record(for: .neon) == nil)
        registry.reconcile(connected: [.anthropic, .neon], now: testNow)
        #expect(registry.record(for: .neon)?.id != first)
    }

    @Test func roundTripsThroughJSON() throws {
        var registry = ConnectionRegistry()
        registry.reconcile(connected: [.google, .twilio], now: testNow)
        let data = try JSONEncoder().encode(registry)
        #expect(try JSONDecoder().decode(ConnectionRegistry.self, from: data) == registry)
        #expect(registry.version == ConnectionRegistry.currentVersion)
    }

    /// The Keychain payload is a JSON object keyed by these field ids. A later migration (and anything that
    /// reads the items) depends on them, so renaming one needs a migration, not just a code change.
    @Test func credentialFieldIDsAreStable() {
        let fields = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, $0.info.fields.map(\.id)) })
        #expect(fields == [
            .anthropic: ["apiKey"],
            .google: ["serviceAccountJSON", "exportTable", "billingAccountID"],
            .openai: ["apiKey"],
            .vercel: ["token", "teamID"],
            .cloudflare: ["token", "accountID"],
            .twilio: ["accountSID", "apiKeySID", "secret"],
            .neon: ["apiKey", "orgID"],
            .supabase: []
        ])
        #expect(Brand.keychainService == "app.killcord.KillCord.providers")
    }
}
