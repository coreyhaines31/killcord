import Foundation

/// Moves keys saved by Kill Cord 0.1.2 and earlier (one Keychain item per provider, account "anthropic")
/// to one item per connection (account = the connection's UUID), keeping each connection's existing id.
///
/// Never loses a key. For each provider-named item:
/// 1. Pick its connection: one whose UUID item already holds the same bytes (an earlier run stopped before
///    deleting), else the oldest connection of that provider with no UUID item, else a new connection.
/// 2. Save the registry before touching the Keychain, so a new id is never lost after its item is written.
/// 3. Write the bytes to the UUID account, read them back, compare.
/// 4. Only then delete the provider-named item.
///
/// Any failure leaves the old item where it is and the connection reading from it (`legacyFallback`), and
/// the next launch tries again. A connection item that can't be read counts as unknown, never empty, so a
/// provider with one waits for the next launch. Running it again after it finished does nothing.
public enum ConnectionMigration {
    public struct Outcome: Sendable, Equatable {
        public var registry: ConnectionRegistry
        /// Connections still reading their provider-named item, because the move didn't verify.
        public var legacyFallback: [UUID: String]
        /// True when no provider-named item is left (or could be left) in the Keychain.
        public var isComplete: Bool
    }

    public static func run(secrets: SecretStore, registry start: ConnectionRegistry, now: Date,
                           makeID: () -> UUID = UUID.init,
                           saveRegistry: (ConnectionRegistry) -> Void) -> Outcome {
        var registry = ConnectionRegistry(records: start.records)
        var fallback: [UUID: String] = [:]
        var complete = true
        for provider in ProviderID.allCases {
            let legacy = provider.rawValue
            let records = registry.records(for: provider)
            let record: ConnectionRecord
            let data: Data
            switch Step(legacy: Item(secrets, account: legacy), records: records, secrets: secrets) {
            case .nothing:
                continue
            case .deleteOnly:
                if (try? secrets.delete(account: legacy)) == nil { complete = false }
                continue
            case .wait(let owner):
                complete = false
                if let owner { fallback[owner] = legacy }
                continue
            case .copy(let bytes, let into):
                data = bytes
                record = into ?? registry.add(provider, now: now, makeID: makeID)
                if into == nil { saveRegistry(registry) }
            }
            if copy(data, to: record, secrets: secrets) {
                if (try? secrets.delete(account: legacy)) == nil { complete = false }
            } else {
                fallback[record.id] = legacy
                complete = false
            }
        }
        saveRegistry(registry)
        return Outcome(registry: registry, legacyFallback: fallback, isComplete: complete)
    }

    /// Writes the bytes to the connection's UUID item and reads them back. False when they don't match.
    private static func copy(_ data: Data, to record: ConnectionRecord, secrets: SecretStore) -> Bool {
        do {
            try secrets.write(data, account: record.keychainAccount, label: CredentialStore.label(record))
            return try secrets.read(account: record.keychainAccount) == data
        } catch {
            return false
        }
    }

    /// What a Keychain item holds. A read error is `unknown`, never `empty`.
    enum Item: Equatable {
        case holds(Data)
        case empty
        case unknown

        init(_ secrets: SecretStore, account: String) {
            do {
                self = try secrets.read(account: account).map(Item.holds) ?? .empty
            } catch {
                self = .unknown
            }
        }
    }

    /// What to do with one provider-named item, given what its provider's connections hold.
    enum Step: Equatable {
        /// No old item.
        case nothing
        /// A connection already holds the same bytes (an earlier run stopped before deleting).
        case deleteOnly
        /// Something couldn't be read: leave the old item, keep it readable for `owner`, retry next launch.
        case wait(owner: UUID?)
        /// Copy into this connection, or a new one when nil.
        case copy(Data, into: ConnectionRecord?)

        init(legacy: Item, records: [ConnectionRecord], secrets: SecretStore) {
            let items = records.map { Item(secrets, account: $0.keychainAccount) }
            let ownerIndex = items.firstIndex(of: .empty) ?? items.firstIndex(of: .unknown)
            let owner = ownerIndex.map { records[$0].id }
            switch legacy {
            case .empty:
                self = .nothing
            case .unknown:
                // Can't tell whether there's an old item. Keep reading it for the connection that would own it.
                self = .wait(owner: owner)
            case .holds(let data) where items.contains(.holds(data)):
                self = .deleteOnly
            case .holds where items.contains(.unknown):
                // A connection we couldn't read may already hold this key, or be the one that should get it.
                // Writing now could copy one key into two connections, so wait for a launch where it reads.
                self = .wait(owner: owner)
            case .holds(let data):
                self = .copy(data, into: items.firstIndex(of: .empty).map { records[$0] })
            }
        }
    }
}
