import Foundation

/// Where secrets live. The app uses `KeychainSecretStore`; tests and demo mode use `InMemorySecretStore`.
/// Nothing else in Kill Cord may write a key anywhere: not files, not UserDefaults, not logs.
public protocol SecretStore: Sendable {
    func read(account: String) throws -> Data?
    /// `label` is what Keychain Access shows. Never part of the secret.
    func write(_ data: Data, account: String, label: String?) throws
    func delete(account: String) throws
}

extension SecretStore {
    public func write(_ data: Data, account: String) throws {
        try write(data, account: account, label: nil)
    }
}

public enum SecretStoreError: Error, Equatable, Sendable, LocalizedError {
    /// A Keychain status code. Never carries the secret.
    case keychain(Int32)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "The Keychain refused the request (error \(status))."
        }
    }
}

/// A test and demo double. Thread-safe.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    public init(_ items: [String: Data] = [:]) {
        self.items = items
    }

    public func read(account: String) throws -> Data? {
        lock.withLock { items[account] }
    }

    public func write(_ data: Data, account: String, label: String?) throws {
        lock.withLock { items[account] = data }
    }

    public func delete(account: String) throws {
        _ = lock.withLock { items.removeValue(forKey: account) }
    }

    public var accounts: [String] {
        lock.withLock { items.keys.sorted() }
    }
}

/// What a person pasted in to connect one provider: field id to value. Its descriptions never print the
/// values, so a stray `print` or string interpolation can't leak a key.
public struct ProviderCredentials: Sendable, Equatable, Codable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public let provider: ProviderID
    private let values: [String: String]

    public init(provider: ProviderID, values: [String: String]) {
        self.provider = provider
        self.values = values.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
    }

    public subscript(field: String) -> String? { values[field] }

    /// The value for a required field, or `.notConfigured`.
    public func require(_ field: String) throws -> String {
        guard let value = values[field] else { throw SpendError.notConfigured }
        return value
    }

    /// Every secret value, so error text and logs can be checked against them.
    public var secrets: [String] {
        provider.info.fields.filter(\.isSecret).compactMap { values[$0.id] }
    }

    /// Required fields that are still empty.
    public var missingFields: [CredentialField] {
        provider.info.fields.filter { !$0.isOptional && values[$0.id] == nil }
    }

    public var description: String {
        let shown = provider.info.fields.compactMap { field -> String? in
            guard values[field.id] != nil else { return nil }
            return "\(field.id): \(field.isSecret ? "<redacted>" : "<set>")"
        }
        return "ProviderCredentials(\(provider.rawValue), \(shown.joined(separator: ", ")))"
    }

    public var debugDescription: String { description }

    /// What Settings shows for each saved field: non-secret values as they are; secrets as their last four
    /// characters only ("ending in 0001"), and a service account key as its account email. A secret shorter
    /// than 16 characters shows no characters at all.
    public var hints: [(field: CredentialField, text: String)] {
        provider.info.fields.compactMap { field in
            guard let value = values[field.id] else { return nil }
            guard field.isSecret else { return (field, value) }
            if field.isMultiline {
                let object = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any]
                let email = object?["client_email"] as? String
                return (field, email ?? "Saved")
            }
            return (field, value.count >= 16 ? "Ending in \(value.suffix(4))" : "Saved")
        }
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["provider": provider, "fields": description], displayStyle: .struct)
    }
}

/// Saves each connection's fields as one Keychain item, account = the connection's UUID. Kill Cord 0.1.2
/// and earlier named the item by provider ("anthropic"); `ConnectionMigration` moves those, and until a move
/// is verified, `legacyFallback` lets the connection keep reading its old item.
public struct CredentialStore: Sendable {
    private let secrets: SecretStore
    /// Connection id to the provider-named account it still reads from, for an unfinished migration.
    public let legacyFallback: [UUID: String]

    public init(secrets: SecretStore, legacyFallback: [UUID: String] = [:]) {
        self.secrets = secrets
        self.legacyFallback = legacyFallback
    }

    public func load(_ connection: ConnectionRecord) throws -> ProviderCredentials? {
        var data = try secrets.read(account: connection.keychainAccount)
        if data == nil, let legacy = legacyFallback[connection.id] {
            data = try secrets.read(account: legacy)
        }
        guard let data else { return nil }
        guard let values = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return ProviderCredentials(provider: connection.provider, values: values)
    }

    /// Whether the connection has an item. Throws when the Keychain can't say.
    public func hasItem(_ connection: ConnectionRecord) throws -> Bool {
        if try secrets.read(account: connection.keychainAccount) != nil { return true }
        guard let legacy = legacyFallback[connection.id] else { return false }
        return try secrets.read(account: legacy) != nil
    }

    /// The account that holds the connection's item now: its own, or its old one until the move finishes.
    public func account(for connection: ConnectionRecord) -> String {
        if ((try? secrets.read(account: connection.keychainAccount)) ?? nil) != nil { return connection.keychainAccount }
        return legacyFallback[connection.id] ?? connection.keychainAccount
    }

    public func save(_ credentials: ProviderCredentials, for connection: ConnectionRecord) throws {
        try secrets.write(Self.encode(credentials), account: connection.keychainAccount,
                          label: Self.label(connection))
        // The new item wins from now on. Drop the old one so a later migration can't bring it back.
        if let legacy = legacyFallback[connection.id] { try? secrets.delete(account: legacy) }
    }

    public func delete(_ connection: ConnectionRecord) throws {
        try secrets.delete(account: connection.keychainAccount)
        if let legacy = legacyFallback[connection.id] { try secrets.delete(account: legacy) }
    }

    /// Deletes these connections' items and every provider-named item from before connections had their
    /// own. For "Remove all local data".
    public func deleteAll(_ connections: [ConnectionRecord]) throws {
        for connection in connections { try secrets.delete(account: connection.keychainAccount) }
        for provider in ProviderID.allCases { try secrets.delete(account: provider.rawValue) }
    }

    /// The item's payload: field id to value, in the provider's field order. Unchanged since 0.1.0.
    static func encode(_ credentials: ProviderCredentials) throws -> Data {
        var values: [String: String] = [:]
        for field in credentials.provider.info.fields {
            if let value = credentials[field.id] { values[field.id] = value }
        }
        return try JSONEncoder().encode(values)
    }

    /// What Keychain Access shows: "Kill Cord: Anthropic 2".
    static func label(_ connection: ConnectionRecord) -> String {
        "\(Brand.name): \(connection.name)"
    }
}

/// Scrubs known secrets out of text before it's shown or logged. A second line of defense: messages are
/// built from fixed strings in the first place.
public enum Redactor {
    public static func redact(_ text: String, secrets: [String]) -> String {
        var result = text
        // Longest first, so a secret that contains another is removed whole.
        for secret in secrets.sorted(by: { $0.count > $1.count }) where secret.count >= 4 {
            result = result.replacingOccurrences(of: secret, with: "<redacted>")
        }
        return result
    }
}
