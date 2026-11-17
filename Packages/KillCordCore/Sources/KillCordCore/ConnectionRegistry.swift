import Foundation

/// One provider connection: one key, saved as one Keychain item whose account is `id`. A person can have
/// several of the same provider (two Anthropic organizations), so the connection, not the provider, owns
/// the key, the name, the alert caps and the readings. Not a secret, and holds no part of the key.
public struct ConnectionRecord: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let provider: ProviderID
    /// When Kill Cord first knew about this connection. For keys saved before records existed, that's the
    /// first launch that adopted them, not the day the key was pasted.
    public let createdAt: Date
    /// What the person calls it. Starts as the provider's name ("Anthropic", then "Anthropic 2").
    public internal(set) var name: String

    public init(id: UUID, provider: ProviderID, createdAt: Date, name: String? = nil) {
        self.id = id
        self.provider = provider
        self.createdAt = createdAt
        self.name = name ?? provider.info.name
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, createdAt, name
    }

    /// Version 1 records (Kill Cord 0.1.2) have no name; they get the provider's.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decode(ProviderID.self, forKey: .provider)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? provider.info.name
    }

    /// The Keychain account that holds this connection's key.
    public var keychainAccount: String { id.uuidString }
}

/// Every connection, versioned. The list of connections Kill Cord knows about: the Keychain items are found
/// through it. Version 1 (Kill Cord 0.1.2) held at most one record per provider and its items were named by
/// provider; `ConnectionMigration` moves those over.
public struct ConnectionRegistry: Sendable, Equatable, Codable {
    public static let currentVersion = 2

    public private(set) var version: Int
    /// In provider order, then oldest first within a provider.
    public private(set) var records: [ConnectionRecord]

    public init(records: [ConnectionRecord] = []) {
        version = Self.currentVersion
        self.records = Self.sorted(records)
    }

    public func record(_ id: UUID) -> ConnectionRecord? {
        records.first { $0.id == id }
    }

    public func records(for provider: ProviderID) -> [ConnectionRecord] {
        records.filter { $0.provider == provider }
    }

    /// Providers with at least one connection, in provider order.
    public var providers: [ProviderID] {
        ProviderID.allCases.filter { provider in records.contains { $0.provider == provider } }
    }

    /// Connection id to name, for the summary and alerts.
    public var names: [UUID: String] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.name) })
    }

    /// The name a new connection of this provider starts with: "Anthropic" when none uses it, else the first
    /// free "Anthropic 2", "Anthropic 3".
    public func defaultName(for provider: ProviderID) -> String {
        let taken = Set(records.map(\.name))
        let base = provider.info.name
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Adds a connection with a new id and the default name.
    @discardableResult
    public mutating func add(_ provider: ProviderID, now: Date, makeID: () -> UUID = UUID.init) -> ConnectionRecord {
        let record = ConnectionRecord(id: makeID(), provider: provider, createdAt: now, name: defaultName(for: provider))
        insert(record)
        return record
    }

    /// Adds a record as it is, keeping its id. Replaces one with the same id.
    public mutating func insert(_ record: ConnectionRecord) {
        records.removeAll { $0.id == record.id }
        records = Self.sorted(records + [record])
        version = Self.currentVersion
    }

    public mutating func remove(_ id: UUID) {
        records.removeAll { $0.id == id }
    }

    /// Renames a connection. Spaces are trimmed; an empty name goes back to the default.
    public mutating func rename(_ id: UUID, to name: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let provider = records[index].provider
            records[index].name = ""
            records[index].name = defaultName(for: provider)
        } else {
            records[index].name = String(trimmed.prefix(60))
        }
    }

    /// Drops records whose Keychain item is gone for sure. `hasItem` throws when the Keychain can't say
    /// (locked, or refused): those records stay. Returns whether anything changed.
    @discardableResult
    public mutating func reconcile(hasItem: (ConnectionRecord) throws -> Bool) -> Bool {
        let kept = records.filter { record in (try? hasItem(record)) ?? true }
        let changed = kept != records || version != Self.currentVersion
        records = kept
        version = Self.currentVersion
        return changed
    }

    private static func sorted(_ records: [ConnectionRecord]) -> [ConnectionRecord] {
        records.sorted {
            if $0.provider != $1.provider { return $0.provider < $1.provider }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
