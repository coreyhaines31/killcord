import Foundation
@testable import KillCordCore
import Testing

@Suite struct LocalAccountSnapshotTests {
    static let connectable = ProviderID.allCases.filter(\.info.connects)

    /// Every connectable provider saved with fake keys, plus settings that touch every snapshot field.
    func everything() throws -> (LocalAccountSnapshot, InMemorySecretStore) {
        let secrets = InMemorySecretStore()
        let store = CredentialStore(secrets: secrets)
        var registry = oneEach(Self.connectable)
        let second = registry.add(.anthropic, now: testNow.addingTimeInterval(60))
        registry.rename(second.id, to: "Client work")
        for record in registry.records {
            try store.save(FakeKeys.credentials(record.provider), for: record)
        }
        var audit = CapAuditState()
        audit.mark("openai-project-budget", .done(at: testNow))
        audit.mark("anthropic-workspace-limit", .notApplicable(at: testNow))
        let thresholds = SpendThresholds(perConnection: [.of(.anthropic): .init(daily: decimal("12.5"))],
                                         providerTotals: [.anthropic: .init(monthly: decimal("900"))],
                                         total: .init(daily: decimal("50"), monthly: decimal("500")))
        let snapshot = LocalAccountSnapshot.make(
            credentials: store, registry: registry,
            state: .init(refreshInterval: 900, menuBarPeriod: .month, thresholds: thresholds, capAudit: audit,
                         firedAlerts: .init(fired: ["total|day|2026-11-15|50"])),
            now: testNow)
        return (snapshot, secrets)
    }

    @Test func neverHoldsAKeyOrAnyFieldValue() throws {
        let (snapshot, _) = try everything()
        let text = try #require(String(data: try snapshot.encoded(), encoding: .utf8))
        for secret in FakeKeys.all {
            #expect(!text.contains(secret))
        }
        // Non-secret fields (account ids, the export table) move with the key, on consent, not here.
        for provider in Self.connectable {
            for field in provider.info.fields {
                guard let value = FakeKeys.credentials(provider)[field.id] else { continue }
                #expect(!text.contains(value), "\(provider) \(field.id) is in the snapshot")
            }
        }
        #expect(!String(describing: snapshot).contains(FakeKeys.anthropic))
    }

    @Test func referencesEachKeychainItemWithItsFields() throws {
        let (snapshot, _) = try everything()
        #expect(snapshot.connections.map(\.provider) == [.anthropic] + Self.connectable)
        #expect(snapshot.connections.prefix(2).map(\.name) == ["Anthropic", "Client work"])
        #expect(Set(snapshot.connections.map(\.id)).count == snapshot.connections.count)
        for connection in snapshot.connections {
            #expect(connection.keychain.account == connection.id.uuidString)
        }
        let google = try #require(snapshot.connections.first { $0.provider == .google })
        #expect(google.keychain == .init(service: Brand.keychainService, account: UUID.of(.google).uuidString,
                                         fieldIDs: ["serviceAccountJSON", "exportTable", "billingAccountID"],
                                         secretFieldIDs: ["serviceAccountJSON"]))
        let twilio = try #require(snapshot.connections.first { $0.provider == .twilio })
        #expect(twilio.keychain.secretFieldIDs == ["secret"])
    }

    @Test func carriesSettingsInPlainShapes() throws {
        let (snapshot, _) = try everything()
        #expect(snapshot.schemaVersion == LocalAccountSnapshot.currentSchemaVersion)
        #expect(snapshot.settings.refreshIntervalSeconds == 900)
        #expect(snapshot.settings.menuBarPeriod == "month")
        #expect(snapshot.settings.thresholds == [
            .init(scope: "connection", id: UUID.of(.anthropic).uuidString, daily: "12.5", monthly: nil),
            .init(scope: "provider", id: "anthropic", daily: nil, monthly: "900"),
            .init(scope: "total", id: nil, daily: "50", monthly: "500")
        ])
        #expect(snapshot.capMarks.map(\.state) == ["notApplicable", "done"])
        #expect(snapshot.firedAlerts == ["total|day|2026-11-15|50"])
        let text = try #require(String(data: try snapshot.encoded(), encoding: .utf8))
        #expect(text.contains("\"2026-11-15T18:30:00Z\""))
    }

    @Test func roundTrips() throws {
        let (snapshot, _) = try everything()
        #expect(try LocalAccountSnapshot.decode(snapshot.encoded()) == snapshot)
    }

    @Test func leavesOutRecordsWhoseKeyIsGone() throws {
        let secrets = InMemorySecretStore()
        let store = CredentialStore(secrets: secrets)
        let registry = oneEach([.anthropic, .neon])
        try store.save(FakeKeys.credentials(.anthropic), for: try #require(registry.record(.of(.anthropic))))
        let snapshot = LocalAccountSnapshot.make(
            credentials: store, registry: registry, state: .init(refreshInterval: 300, menuBarPeriod: .today),
            now: testNow)
        #expect(snapshot.connections.map(\.provider) == [.anthropic])
        #expect(snapshot.settings.thresholds.isEmpty)
    }

    @Test func makingItLeavesTheKeychainItemsAsTheyWere() throws {
        let secrets = InMemorySecretStore()
        let store = CredentialStore(secrets: secrets)
        let registry = oneEach(Self.connectable)
        for record in registry.records { try store.save(FakeKeys.credentials(record.provider), for: record) }
        let before = try secrets.accounts.map { try secrets.read(account: $0) }
        _ = LocalAccountSnapshot.make(credentials: store, registry: registry,
                                      state: .init(refreshInterval: 300, menuBarPeriod: .today), now: testNow)
        #expect(try secrets.accounts.map { try secrets.read(account: $0) } == before)
        for record in registry.records {
            #expect(try store.load(record) == FakeKeys.credentials(record.provider))
        }
    }

    @Test func pointsAtTheOldItemWhileAMoveIsUnfinished() throws {
        let secrets = InMemorySecretStore()
        try secrets.write(CredentialStore.encode(FakeKeys.credentials(.neon)), account: "neon")
        let registry = oneEach([.neon])
        let store = CredentialStore(secrets: secrets, legacyFallback: [.of(.neon): "neon"])
        let snapshot = LocalAccountSnapshot.make(
            credentials: store, registry: registry, state: .init(refreshInterval: 300, menuBarPeriod: .today),
            now: testNow)
        #expect(snapshot.connections.map(\.keychain.account) == ["neon"])
    }
}
