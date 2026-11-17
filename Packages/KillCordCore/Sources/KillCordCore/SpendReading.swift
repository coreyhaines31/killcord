import Foundation

/// One spend reading in a plain, versioned JSON shape: amounts as decimal strings, ISO 8601 dates, no Swift
/// enum encodings. It's what a readings-only sync would send (the default for a future cloud account, where
/// keys stay on the Mac). Built from a `SpendSnapshot` alone, so it can't carry a key: it never sees one.
///
/// Nothing in the app sends or writes this today.
public struct SpendReading: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public struct Amount: Sendable, Equatable, Codable {
        /// Decimal string, "18.42".
        public let amount: String
        /// ISO 4217, "USD".
        public let currency: String
    }

    public struct Usage: Sendable, Equatable, Codable {
        public let id: String
        public let name: String
        /// Decimal string.
        public let value: String
        public let unit: String
    }

    public let schemaVersion: Int
    /// The `ConnectionRecord` id, so readings from two Macs for the same provider stay apart.
    public let connectionID: UUID
    public let provider: ProviderID
    public let today: Amount?
    public let month: Amount?
    /// "calendarMonth" or "billingPeriod".
    public let monthKind: String
    /// Set when `monthKind` is "billingPeriod".
    public let periodStart: Date?
    public let usage: [Usage]
    public let isEstimate: Bool
    public let dataAsOf: Date?
    public let fetchedAt: Date

    public init(_ snapshot: SpendSnapshot, connectionID: UUID) {
        func amount(_ money: Money?) -> Amount? {
            money.map { Amount(amount: $0.amount.description, currency: $0.currency.code) }
        }
        schemaVersion = Self.currentSchemaVersion
        self.connectionID = connectionID
        provider = snapshot.provider
        today = amount(snapshot.today)
        month = amount(snapshot.month)
        switch snapshot.monthKind {
        case .calendarMonth:
            monthKind = "calendarMonth"
            periodStart = nil
        case .billingPeriod(let start):
            monthKind = "billingPeriod"
            periodStart = start
        }
        usage = snapshot.usage.map { Usage(id: $0.id, name: $0.name, value: $0.value.description, unit: $0.unit) }
        isEstimate = snapshot.isEstimate
        dataAsOf = snapshot.dataAsOf
        fetchedAt = snapshot.fetchedAt
    }

    /// The latest reading for each recorded connection that has one. Providers with no record are left out.
    public static func all(states: [ProviderState], registry: ConnectionRegistry) -> [SpendReading] {
        states.sorted { $0.provider < $1.provider }.compactMap { state in
            guard let snapshot = state.snapshot, let record = registry.record(for: state.provider) else { return nil }
            return SpendReading(snapshot, connectionID: record.id)
        }
    }
}
