import Foundation

/// A stable identity for one provider connection, so a later move (to another Mac, or to an account) can
/// refer to "this Anthropic connection" without using the key itself. Not a secret, and holds no part of the
/// key. Kept beside the Keychain item, never inside it, so the item is never rewritten for this.
public struct ConnectionRecord: Sendable, Equatable, Codable {
    public let id: UUID
    public let provider: ProviderID
    /// When Kill Cord first knew about this connection. For keys saved before records existed, that's the
    /// first launch that adopted them, not the day the key was pasted.
    public let createdAt: Date

    public init(id: UUID, provider: ProviderID, createdAt: Date) {
        self.id = id
        self.provider = provider
        self.createdAt = createdAt
    }
}

/// Every connection's record, versioned. Rebuilt from the Keychain on each launch, so it can never claim a
/// connection that isn't saved, and a lost record only means a new id.
public struct ConnectionRegistry: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public private(set) var version: Int
    public private(set) var records: [ConnectionRecord]

    public init(records: [ConnectionRecord] = []) {
        version = Self.currentVersion
        self.records = records.sorted { $0.provider < $1.provider }
    }

    public func record(for provider: ProviderID) -> ConnectionRecord? {
        records.first { $0.provider == provider }
    }

    /// Matches the records to the providers that have a Keychain item: adds a record for each new one, drops
    /// records whose item is gone, and keeps every existing id. Replacing a key keeps its id. Returns whether
    /// anything changed, so the caller saves only then.
    @discardableResult
    public mutating func reconcile(connected: [ProviderID], now: Date, makeID: () -> UUID = UUID.init) -> Bool {
        let wanted = Set(connected)
        var next = records.filter { wanted.contains($0.provider) }
        for provider in wanted.sorted() where !next.contains(where: { $0.provider == provider }) {
            next.append(ConnectionRecord(id: makeID(), provider: provider, createdAt: now))
        }
        next.sort { $0.provider < $1.provider }
        let changed = next != records || version != Self.currentVersion
        records = next
        version = Self.currentVersion
        return changed
    }
}
