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
/// the next launch tries again. Running it again after it finished does nothing.
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
            let data: Data
            do {
                guard let found = try secrets.read(account: legacy) else { continue }
                data = found
            } catch {
                // Can't tell whether there's an old item. Keep reading it for the connection that would own it.
                complete = false
                if let record = registry.records(for: provider).first(where: { !hasUUIDItem($0, secrets) }) {
                    fallback[record.id] = legacy
                }
                continue
            }
            let records = registry.records(for: provider)
            let uuidData = records.map { try? secrets.read(account: $0.keychainAccount) }
            if uuidData.contains(where: { $0 == data }) {
                // Copied before; only the delete is left.
                do { try secrets.delete(account: legacy) } catch { complete = false }
                continue
            }
            let record: ConnectionRecord
            if let index = uuidData.firstIndex(where: { $0 == nil }) {
                record = records[index]
            } else {
                record = registry.add(provider, now: now, makeID: makeID)
                saveRegistry(registry)
            }
            do {
                try secrets.write(data, account: record.keychainAccount, label: CredentialStore.label(record))
                guard try secrets.read(account: record.keychainAccount) == data else {
                    throw MigrationError.readBackMismatch
                }
            } catch {
                fallback[record.id] = legacy
                complete = false
                continue
            }
            do { try secrets.delete(account: legacy) } catch { complete = false }
        }
        saveRegistry(registry)
        return Outcome(registry: registry, legacyFallback: fallback, isComplete: complete)
    }

    private static func hasUUIDItem(_ record: ConnectionRecord, _ secrets: SecretStore) -> Bool {
        ((try? secrets.read(account: record.keychainAccount)) ?? nil) != nil
    }

    enum MigrationError: Error {
        case readBackMismatch
    }
}
