import Foundation
@testable import KillCordCore
import Testing

/// Every path through the move from provider-named Keychain items (0.1.2) to one item per connection. Fake
/// keys and the in-memory store only.
@Suite struct ConnectionMigrationTests {
    /// The in-memory store, with switches to fail the next write, return other bytes on read-back, refuse a
    /// read or a delete, or stop the run (a crash) right after a given write.
    final class FlakyStore: SecretStore, @unchecked Sendable {
        let inner = InMemorySecretStore()
        var failWrites = false
        var corruptReadBack = false
        var unreadable: Set<String> = []
        var undeletable: Set<String> = []
        private var written: Set<String> = []

        func read(account: String) throws -> Data? {
            if unreadable.contains(account) { throw SecretStoreError.keychain(-25308) }
            let data = try inner.read(account: account)
            if corruptReadBack, written.contains(account) { return Data("garbled".utf8) }
            return data
        }

        func write(_ data: Data, account: String, label: String?) throws {
            if failWrites { throw SecretStoreError.keychain(-25299) }
            written.insert(account)
            try inner.write(data, account: account, label: label)
        }

        func delete(account: String) throws {
            if undeletable.contains(account) { throw SecretStoreError.keychain(-25244) }
            try inner.delete(account: account)
        }
    }

    func legacy(_ store: SecretStore, _ providers: [ProviderID]) throws {
        for provider in providers {
            try store.write(CredentialStore.encode(FakeKeys.credentials(provider)), account: provider.rawValue)
        }
    }

    func run(_ store: SecretStore, _ registry: ConnectionRegistry, saves: inout [ConnectionRegistry],
             ids: [UUID] = []) -> ConnectionMigration.Outcome {
        var pending = ids
        var log: [ConnectionRegistry] = []
        let outcome = ConnectionMigration.run(secrets: store, registry: registry, now: testNow,
                                              makeID: { pending.isEmpty ? UUID() : pending.removeFirst() },
                                              saveRegistry: { log.append($0) })
        saves += log
        return outcome
    }

    @Test func freshInstallHasNothingToMove() {
        let store = InMemorySecretStore()
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, ConnectionRegistry(), saves: &saves)
        #expect(outcome.isComplete)
        #expect(outcome.registry.records.isEmpty)
        #expect(outcome.legacyFallback.isEmpty)
        #expect(store.accounts.isEmpty)
    }

    @Test func oneProviderMovesToItsExistingID() throws {
        let store = InMemorySecretStore()
        try legacy(store, [.anthropic])
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, oneEach([.anthropic]), saves: &saves)
        #expect(outcome.isComplete)
        #expect(outcome.registry.records.map(\.id) == [.of(.anthropic)])
        #expect(outcome.registry.version == 2)
        #expect(store.accounts == [UUID.of(.anthropic).uuidString])
        let record = try #require(outcome.registry.record(.of(.anthropic)))
        #expect(try CredentialStore(secrets: store).load(record) == FakeKeys.credentials(.anthropic))
    }

    @Test func manyProvidersAllMoveAndKeepTheirIDs() throws {
        let store = InMemorySecretStore()
        let providers: [ProviderID] = [.anthropic, .google, .openai, .vercel, .cloudflare, .twilio, .neon]
        try legacy(store, providers)
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, oneEach(providers), saves: &saves)
        #expect(outcome.isComplete)
        #expect(Set(outcome.registry.records.map(\.id)) == Set(providers.map { UUID.of($0) }))
        #expect(Set(store.accounts) == Set(providers.map { UUID.of($0).uuidString }))
        let keys = CredentialStore(secrets: store)
        for record in outcome.registry.records {
            #expect(try keys.load(record) == FakeKeys.credentials(record.provider))
        }
    }

    @Test func anItemWithNoRecordGetsANewConnectionSavedBeforeItsKeyIsWritten() throws {
        let store = InMemorySecretStore()
        try legacy(store, [.neon])
        let id = UUID.of(.neon, 9)
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, ConnectionRegistry(), saves: &saves, ids: [id])
        #expect(outcome.isComplete)
        #expect(outcome.registry.records.map(\.id) == [id])
        // The first save names the new id, before the Keychain write could leave an orphan item.
        #expect(saves.first?.record(id) != nil)
        #expect(store.accounts == [id.uuidString])
    }

    @Test func interruptedAfterTheCopyFinishesByDeletingTheOldItem() throws {
        // The previous launch wrote the UUID item and stopped before deleting the old one.
        let store = InMemorySecretStore()
        try legacy(store, [.openai])
        try store.write(CredentialStore.encode(FakeKeys.credentials(.openai)), account: UUID.of(.openai).uuidString)
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, oneEach([.openai]), saves: &saves)
        #expect(outcome.isComplete)
        #expect(store.accounts == [UUID.of(.openai).uuidString])
        #expect(outcome.registry.records.count == 1)
    }

    @Test func interruptedBeforeTheCopyFinishesOnTheNextLaunch() throws {
        // The previous launch saved a new record for an unrecorded item, then stopped.
        let store = InMemorySecretStore()
        try legacy(store, [.vercel])
        let registry = oneEach([.vercel])
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, registry, saves: &saves, ids: [UUID.of(.vercel, 5)])
        #expect(outcome.isComplete)
        #expect(outcome.registry.records.map(\.id) == [.of(.vercel)])
        #expect(store.accounts == [UUID.of(.vercel).uuidString])
    }

    @Test func halfwayThroughManyProvidersResumesWithoutTouchingTheFinishedOnes() throws {
        let store = FlakyStore()
        try legacy(store.inner, [.anthropic, .openai, .neon])
        store.undeletable = ["openai"]
        var saves: [ConnectionRegistry] = []
        let first = run(store, oneEach([.anthropic, .openai, .neon]), saves: &saves)
        #expect(!first.isComplete)
        #expect(Set(store.inner.accounts) == Set(["openai"] + [UUID.of(.anthropic), .of(.openai), .of(.neon)]
            .map(\.uuidString)))
        // The copy is verified, so the connection reads its own item already.
        #expect(first.legacyFallback.isEmpty)
        store.undeletable = []
        let second = run(store, first.registry, saves: &saves)
        #expect(second.isComplete)
        #expect(second.registry == first.registry)
        #expect(Set(store.inner.accounts) == Set([UUID.of(.anthropic), .of(.openai), .of(.neon)].map(\.uuidString)))
        let keys = CredentialStore(secrets: store.inner)
        for record in second.registry.records {
            #expect(try keys.load(record) == FakeKeys.credentials(record.provider))
        }
    }

    @Test func aReadBackMismatchKeepsTheOldItemAndReadsFromIt() throws {
        let store = FlakyStore()
        try legacy(store.inner, [.anthropic])
        store.corruptReadBack = true
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, oneEach([.anthropic]), saves: &saves)
        #expect(!outcome.isComplete)
        #expect(outcome.legacyFallback == [.of(.anthropic): "anthropic"])
        #expect(store.inner.accounts.contains("anthropic"))
        // The key still works this launch, through the old item.
        store.corruptReadBack = false
        let keys = CredentialStore(secrets: store.inner, legacyFallback: outcome.legacyFallback)
        try store.inner.delete(account: UUID.of(.anthropic).uuidString)
        #expect(try keys.load(#require(outcome.registry.record(.of(.anthropic)))) == FakeKeys.credentials(.anthropic))
        // Next launch, with a Keychain that behaves, finishes.
        let retry = run(store, outcome.registry, saves: &saves)
        #expect(retry.isComplete)
        #expect(store.inner.accounts == [UUID.of(.anthropic).uuidString])
    }

    @Test func aFailedWriteKeepsTheOldItem() throws {
        let store = FlakyStore()
        try legacy(store.inner, [.twilio])
        store.failWrites = true
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, oneEach([.twilio]), saves: &saves)
        #expect(!outcome.isComplete)
        #expect(outcome.legacyFallback == [.of(.twilio): "twilio"])
        #expect(store.inner.accounts == ["twilio"])
    }

    @Test func anUnreadableOldItemIsLeftAloneAndRetried() throws {
        let store = FlakyStore()
        try legacy(store.inner, [.cloudflare])
        store.unreadable = ["cloudflare"]
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, oneEach([.cloudflare]), saves: &saves)
        #expect(!outcome.isComplete)
        #expect(outcome.legacyFallback == [.of(.cloudflare): "cloudflare"])
        #expect(store.inner.accounts == ["cloudflare"])
    }

    @Test func anUnreadableConnectionItemIsNeverTreatedAsEmpty() throws {
        // Two Anthropic connections. The first one's own item can't be read this launch; the second has none.
        let store = FlakyStore()
        let first = UUID.of(.anthropic), second = UUID.of(.anthropic, 2)
        let mine = ProviderCredentials(provider: .anthropic, values: ["apiKey": FakeKeys.anthropic + "-mine"])
        try store.inner.write(CredentialStore.encode(mine), account: first.uuidString)
        try legacy(store.inner, [.anthropic])
        store.unreadable = [first.uuidString]
        var registry = ConnectionRegistry(records: [ConnectionRecord(id: first, provider: .anthropic, createdAt: testNow)])
        _ = registry.add(.anthropic, now: testNow, makeID: { second })
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, registry, saves: &saves)
        #expect(!outcome.isComplete)
        #expect(outcome.registry.records.map(\.id) == [first, second])
        #expect(outcome.legacyFallback == [second: "anthropic"])
        // Nothing written or deleted: the first connection keeps its own key, the old item stays.
        #expect(try store.inner.read(account: first.uuidString) == CredentialStore.encode(mine))
        #expect(try store.inner.read(account: second.uuidString) == nil)
        #expect(store.inner.accounts.contains("anthropic"))

        // Next launch the read works and the move finishes onto the empty connection.
        store.unreadable = []
        let retry = run(store, outcome.registry, saves: &saves)
        #expect(retry.isComplete)
        #expect(retry.legacyFallback.isEmpty)
        #expect(try store.inner.read(account: first.uuidString) == CredentialStore.encode(mine))
        let keys = CredentialStore(secrets: store)
        let record = try #require(retry.registry.record(second))
        #expect(try keys.load(record) == FakeKeys.credentials(.anthropic))
        #expect(!store.inner.accounts.contains("anthropic"))
    }

    @Test func anUnreadableOnlyConnectionGetsNoNewConnection() throws {
        let store = FlakyStore()
        try legacy(store.inner, [.vercel])
        store.unreadable = [UUID.of(.vercel).uuidString]
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, oneEach([.vercel]), saves: &saves)
        #expect(!outcome.isComplete)
        #expect(outcome.registry.records.map(\.id) == [.of(.vercel)])
        #expect(outcome.legacyFallback == [.of(.vercel): "vercel"])
        #expect(store.inner.accounts == ["vercel"])
    }

    @Test func runningAgainAfterItFinishedChangesNothing() throws {
        let store = InMemorySecretStore()
        try legacy(store, [.anthropic, .google])
        var saves: [ConnectionRegistry] = []
        let first = run(store, oneEach([.anthropic, .google]), saves: &saves)
        let before = try store.accounts.map { try store.read(account: $0) }
        let second = run(store, first.registry, saves: &saves)
        #expect(second == first)
        #expect(try store.accounts.map { try store.read(account: $0) } == before)
    }

    @Test func anOldItemSavedByADowngradedAppBecomesAnotherConnection() throws {
        // Migrated, then 0.1.2 ran again and saved a different key under the provider name.
        let store = InMemorySecretStore()
        try store.write(CredentialStore.encode(FakeKeys.credentials(.anthropic)), account: UUID.of(.anthropic).uuidString)
        try store.write(CredentialStore.encode(ProviderCredentials(provider: .anthropic,
                                                                    values: ["apiKey": FakeKeys.anthropic + "-new"])),
                        account: "anthropic")
        var saves: [ConnectionRegistry] = []
        let outcome = run(store, oneEach([.anthropic]), saves: &saves, ids: [UUID.of(.anthropic, 2)])
        #expect(outcome.isComplete)
        #expect(outcome.registry.records(for: .anthropic).map(\.name) == ["Anthropic", "Anthropic 2"])
        let keys = CredentialStore(secrets: store)
        let loaded = try outcome.registry.records.map { try keys.load($0)?["apiKey"] }
        #expect(loaded == [FakeKeys.anthropic, FakeKeys.anthropic + "-new"])
    }

    @Test func movesPerProviderAlertsAndSentAlertsOntoTheConnection() throws {
        var thresholds = try JSONDecoder().decode(SpendThresholds.self, from: Data("""
        {"perProvider":["anthropic",{"daily":50},"vercel",{"monthly":20}],"total":{"daily":100}}
        """.utf8))
        let registry = oneEach([.anthropic])
        let moved = thresholds.migrateLegacy(registry)
        #expect(moved)
        #expect(thresholds.perConnection == [.of(.anthropic): .init(daily: 50)])
        // Vercel isn't connected: its limit becomes the provider total, which is the same limit.
        #expect(thresholds.providerTotals == [.vercel: .init(monthly: 20)])
        #expect(thresholds.total == .init(daily: 100))
        let movedAgain = thresholds.migrateLegacy(registry)
        #expect(!movedAgain)
        let again = try JSONDecoder().decode(SpendThresholds.self, from: JSONEncoder().encode(thresholds))
        #expect(again == thresholds)

        let fired = ThresholdPlanner.State(fired: ["anthropic|day|2026-11-15|50", "total|day|2026-11-15|100",
                                                    "vercel|month|2026-11|20"])
        #expect(fired.migrated(registry).fired == ["\(UUID.of(.anthropic).uuidString)|day|2026-11-15|50",
                                                   "total|day|2026-11-15|100", "vercel|month|2026-11|20"])
    }
}
