import Foundation

/// Everything a later move (to a Kill Cord Cloud account, or another Mac) would need from this Mac, in one
/// versioned, plain JSON shape: settings, thresholds, caps audit marks, and each connection (several can
/// share a provider, each with its own id, name and Keychain item). Keys are never
/// in it. Each connection names its Keychain item and which fields are saved there, so the key can be read
/// at the moment the person agrees to move it, and not before.
///
/// Nothing in the app sends or writes this today. It exists so a future migration reads one function
/// instead of every preference, and so tests can prove no secret is in it.
public struct LocalAccountSnapshot: Sendable, Equatable, Codable {
    /// 2: connections are per connection, not per provider: each has a name, its Keychain account is its
    /// id, and thresholds are scoped to a connection, a provider total, or the overall total.
    public static let currentSchemaVersion = 2

    public struct Settings: Sendable, Equatable, Codable {
        public let refreshIntervalSeconds: Double
        /// `SpendText.MenuBarPeriod` raw value: "today" or "month".
        public let menuBarPeriod: String
        public let thresholds: [Threshold]
    }

    /// One alert threshold. Amounts are USD decimal strings ("50", "12.5"), so no reader loses precision.
    public struct Threshold: Sendable, Equatable, Codable {
        /// "connection", "provider" (every connection of it together), or "total".
        public let scope: String
        /// The connection id for "connection", the provider id for "provider", nil for "total".
        public let id: String?
        public let daily: String?
        public let monthly: String?
    }

    /// Where a connection's fields are saved. Holds no value from them, secret or not.
    public struct KeychainReference: Sendable, Equatable, Codable {
        public let service: String
        public let account: String
        /// Every field saved in the item, in the provider's field order.
        public let fieldIDs: [String]
        /// The subset that is secret, so a review screen can say what moving it would hand over.
        public let secretFieldIDs: [String]
    }

    public struct Connection: Sendable, Equatable, Codable {
        public let id: UUID
        public let provider: ProviderID
        /// What the person calls it ("Anthropic 2", "Client work"). Not a secret.
        public let name: String
        public let createdAt: Date
        public let keychain: KeychainReference
    }

    public struct CapMark: Sendable, Equatable, Codable {
        public let capID: String
        /// "done" or "notApplicable".
        public let state: String
        public let markedAt: Date
    }

    public let schemaVersion: Int
    public let createdAt: Date
    public let settings: Settings
    public let connections: [Connection]
    public let capMarks: [CapMark]
    /// Threshold alerts already sent this period ("<connection id>|day|2026-11-15|50"), so a new home for the alerts
    /// doesn't send them twice.
    public let firedAlerts: [String]

    /// The non-secret settings and state the app keeps in its preferences, gathered for `make`.
    public struct LocalState: Sendable, Equatable {
        public var refreshInterval: TimeInterval
        public var menuBarPeriod: SpendText.MenuBarPeriod
        public var thresholds: SpendThresholds
        public var capAudit: CapAuditState
        public var firedAlerts: ThresholdPlanner.State

        public init(refreshInterval: TimeInterval, menuBarPeriod: SpendText.MenuBarPeriod,
                    thresholds: SpendThresholds = .init(), capAudit: CapAuditState = .init(),
                    firedAlerts: ThresholdPlanner.State = .init()) {
            self.refreshInterval = refreshInterval
            self.menuBarPeriod = menuBarPeriod
            self.thresholds = thresholds
            self.capAudit = capAudit
            self.firedAlerts = firedAlerts
        }
    }

    /// Builds the snapshot. Reads the credential store only to learn which fields are saved; values are
    /// dropped on the spot. A connection with no record, or a record with no saved item, is left out.
    public static func make(credentials: CredentialStore, registry: ConnectionRegistry, state: LocalState,
                            keychainService: String = Brand.keychainService, now: Date) -> LocalAccountSnapshot {
        let connections = registry.records.compactMap { record -> Connection? in
            guard let saved = try? credentials.load(record) else { return nil }
            let fields = record.provider.info.fields.filter { saved[$0.id] != nil }
            return Connection(
                id: record.id, provider: record.provider, name: record.name, createdAt: record.createdAt,
                keychain: KeychainReference(service: keychainService, account: credentials.account(for: record),
                                            fieldIDs: fields.map(\.id),
                                            secretFieldIDs: fields.filter(\.isSecret).map(\.id)))
        }
        let marks = state.capAudit.marks.map { capID, mark in
            switch mark {
            case .done(let at): CapMark(capID: capID, state: "done", markedAt: at)
            case .notApplicable(let at): CapMark(capID: capID, state: "notApplicable", markedAt: at)
            }
        }
        let settings = Settings(refreshIntervalSeconds: state.refreshInterval,
                                menuBarPeriod: state.menuBarPeriod.rawValue, thresholds: thresholds(state.thresholds))
        return LocalAccountSnapshot(schemaVersion: currentSchemaVersion, createdAt: now, settings: settings,
                                    connections: connections, capMarks: marks.sorted { $0.capID < $1.capID },
                                    firedAlerts: state.firedAlerts.fired.sorted())
    }

    private static func thresholds(_ thresholds: SpendThresholds) -> [Threshold] {
        // Decimal's description is locale independent: "12.5", never "12,5".
        func text(_ value: Decimal?) -> String? { value.map(\.description) }
        var rows = thresholds.perConnection.filter { !$0.value.isEmpty }
            .sorted { $0.key.uuidString < $1.key.uuidString }.map {
                Threshold(scope: "connection", id: $0.key.uuidString, daily: text($0.value.daily),
                          monthly: text($0.value.monthly))
            }
        rows += thresholds.providerTotals.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.map {
            Threshold(scope: "provider", id: $0.key.rawValue, daily: text($0.value.daily),
                      monthly: text($0.value.monthly))
        }
        if !thresholds.total.isEmpty {
            rows.append(Threshold(scope: "total", id: nil, daily: text(thresholds.total.daily),
                                  monthly: text(thresholds.total.monthly)))
        }
        return rows
    }

    /// Stable JSON: sorted keys and ISO 8601 dates, readable by any language.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LocalAccountSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LocalAccountSnapshot.self, from: data)
    }
}
