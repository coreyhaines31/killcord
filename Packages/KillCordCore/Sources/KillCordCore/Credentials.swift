import Foundation

/// Where secrets live. The app uses `KeychainSecretStore`; tests and demo mode use `InMemorySecretStore`.
/// Nothing else in Kill Cord may write a key anywhere: not files, not UserDefaults, not logs.
public protocol SecretStore: Sendable {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(account: String) throws
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

    public func write(_ data: Data, account: String) throws {
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

    public var customMirror: Mirror {
        Mirror(self, children: ["provider": provider, "fields": description], displayStyle: .struct)
    }
}

/// Saves each provider's credentials as one Keychain item (account = provider id).
public struct CredentialStore: Sendable {
    private let secrets: SecretStore

    public init(secrets: SecretStore) {
        self.secrets = secrets
    }

    public func load(_ provider: ProviderID) throws -> ProviderCredentials? {
        guard let data = try secrets.read(account: provider.rawValue) else { return nil }
        guard let values = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return ProviderCredentials(provider: provider, values: values)
    }

    public func save(_ credentials: ProviderCredentials) throws {
        var values: [String: String] = [:]
        for field in credentials.provider.info.fields {
            if let value = credentials[field.id] { values[field.id] = value }
        }
        let data = try JSONEncoder().encode(values)
        try secrets.write(data, account: credentials.provider.rawValue)
    }

    public func delete(_ provider: ProviderID) throws {
        try secrets.delete(account: provider.rawValue)
    }

    /// Providers that have something saved.
    public func connected() -> [ProviderID] {
        ProviderID.allCases.filter { (try? secrets.read(account: $0.rawValue)) != nil }
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
