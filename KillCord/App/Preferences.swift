import Foundation
import KillCordCore

/// Settings and small state in UserDefaults. Nothing here is a secret: keys live only in the Keychain.
enum Preferences {
    /// Where everything here is kept. Tests and render harnesses swap in their own suite, so they never
    /// read or write the real app's settings.
    nonisolated(unsafe) static var defaults = UserDefaults.standard

    static let appliedLaunchAtLoginDefaultKey = "appliedLaunchAtLoginDefault"
    static let refreshIntervalKey = "refreshInterval"
    static let menuBarPeriodKey = "menuBarPeriod"
    static let thresholdsKey = "thresholds"
    static let firedAlertsKey = "firedAlerts"
    static let capAuditKey = "capAudit"
    /// Kill Cord 0.1.2's version 1 registry (one record per provider). Read once by the migration, then removed.
    static let connectionsKey = "connections"
    /// The version 2 registry. A new key, so running 0.1.2 again can't rewrite it.
    static let connectionRegistryKey = "connectionRegistry"
    static let localDataVersionKey = "localDataVersion"

    /// Bumped when the shape of anything saved here changes, so a later version (or a move to another Mac
    /// or an account) knows what it's reading. 0 means saved before versioning (Kill Cord 0.1.1 and earlier),
    /// 1 is 0.1.2 (one connection per provider), 2 is connections with their own keys, names and alerts.
    static let currentLocalDataVersion = 2

    static func registerDefaults() {
        defaults.register(defaults: [
            refreshIntervalKey: RefreshScheduler.defaultInterval,
            menuBarPeriodKey: SpendText.MenuBarPeriod.today.rawValue
        ])
    }

    static var appliedLaunchAtLoginDefault: Bool {
        get { defaults.bool(forKey: appliedLaunchAtLoginDefaultKey) }
        set { defaults.set(newValue, forKey: appliedLaunchAtLoginDefaultKey) }
    }

    static var refreshInterval: TimeInterval {
        let value = defaults.double(forKey: refreshIntervalKey)
        return RefreshScheduler.intervalChoices.contains(value) ? value : RefreshScheduler.defaultInterval
    }

    static var menuBarPeriod: SpendText.MenuBarPeriod {
        SpendText.MenuBarPeriod(rawValue: defaults.string(forKey: menuBarPeriodKey) ?? "") ?? .today
    }

    static var thresholds: SpendThresholds {
        get { load(SpendThresholds.self, thresholdsKey) ?? SpendThresholds() }
        set { save(newValue, thresholdsKey) }
    }

    static var firedAlerts: ThresholdPlanner.State {
        get { load(ThresholdPlanner.State.self, firedAlertsKey) ?? .init() }
        set { save(newValue, firedAlertsKey) }
    }

    static var capAudit: CapAuditState {
        get { load(CapAuditState.self, capAuditKey) ?? CapAuditState() }
        set { save(newValue, capAuditKey) }
    }

    static var connections: ConnectionRegistry {
        get {
            load(ConnectionRegistry.self, connectionRegistryKey)
                ?? load(ConnectionRegistry.self, connectionsKey)
                ?? ConnectionRegistry()
        }
        set { save(newValue, connectionRegistryKey) }
    }

    /// Brings everything saved by an older version up to date, at launch. Keychain items move to one per
    /// connection (verified before the old one is deleted, retried every launch until done), then the
    /// per-provider alert limits and sent alerts move onto those connections, once. Returns the connections
    /// that must still read their old item.
    static func migrate(secrets: SecretStore, now: Date = Date()) -> [UUID: String] {
        let outcome = ConnectionMigration.run(secrets: secrets, registry: connections, now: now) { connections = $0 }
        if defaults.integer(forKey: localDataVersionKey) < currentLocalDataVersion {
            var limits = thresholds
            if limits.migrateLegacy(outcome.registry) { thresholds = limits }
            firedAlerts = firedAlerts.migrated(outcome.registry)
            defaults.set(currentLocalDataVersion, forKey: localDataVersionKey)
        }
        if outcome.isComplete { defaults.removeObject(forKey: connectionsKey) }
        return outcome.legacyFallback
    }

    /// Every key Kill Cord writes to UserDefaults, for "Remove all local data".
    static let allKeys = [appliedLaunchAtLoginDefaultKey, refreshIntervalKey, menuBarPeriodKey, thresholdsKey,
                          firedAlertsKey, capAuditKey, connectionsKey, connectionRegistryKey, localDataVersionKey]

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

/// The last spend Kill Cord read per connection, saved so a relaunch can show it (clearly marked not
/// live). A file from 0.1.2 has no connection ids and is ignored. Amounts and times only:
/// ~/Library/Application Support/Kill Cord/spend.json.
enum SpendCache {
    /// Tests point this at a temporary folder.
    nonisolated(unsafe) static var folder = Brand.supportFolder
    static var url: URL { folder.appendingPathComponent("spend.json") }

    static func load() -> [ProviderState] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ProviderState].self, from: data)) ?? []
    }

    static func save(_ states: [ProviderState]) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: folder)
    }
}
