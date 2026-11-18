import Foundation
import KillCordCore

// MARK: - Balances and custom connections

extension SpendModel {
    /// Connections that report a balance, or will once read. In registry order.
    var balanceConnections: [ConnectionRecord] {
        registry.records.filter { $0.provider.info.capability.showsBalance || states[$0.id]?.snapshot?.balance != nil }
    }

    var hasBalances: Bool { orderedStates.contains { $0.snapshot?.balance != nil } }

    /// A custom connection's saved setup, read from the Keychain. Nil for other providers.
    func customConfig(_ id: UUID) -> CustomConfig? {
        guard registry.record(id)?.provider == .custom, let stored = storedCredentials(id) else { return nil }
        return try? CustomConfig(stored)
    }
}

extension ConnectionRegistry {
    /// Adds a connection. A custom one starts with the service's own name.
    mutating func adding(_ provider: ProviderID, named name: String?) -> ConnectionRecord {
        let record = add(provider, now: Date())
        guard provider == .custom, let name else { return record }
        rename(record.id, to: name)
        return self.record(record.id) ?? record
    }
}
