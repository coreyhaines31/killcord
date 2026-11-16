import Foundation
import KillCordCore

/// Settings and small state in UserDefaults. Nothing here is a secret: keys live only in the Keychain.
enum Preferences {
    static let appliedLaunchAtLoginDefaultKey = "appliedLaunchAtLoginDefault"
    static let refreshIntervalKey = "refreshInterval"
    static let menuBarPeriodKey = "menuBarPeriod"
    static let thresholdsKey = "thresholds"
    static let firedAlertsKey = "firedAlerts"
    static let capAuditKey = "capAudit"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            refreshIntervalKey: RefreshScheduler.defaultInterval,
            menuBarPeriodKey: SpendText.MenuBarPeriod.today.rawValue
        ])
    }

    static var appliedLaunchAtLoginDefault: Bool {
        get { UserDefaults.standard.bool(forKey: appliedLaunchAtLoginDefaultKey) }
        set { UserDefaults.standard.set(newValue, forKey: appliedLaunchAtLoginDefaultKey) }
    }

    static var refreshInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: refreshIntervalKey)
        return RefreshScheduler.intervalChoices.contains(value) ? value : RefreshScheduler.defaultInterval
    }

    static var menuBarPeriod: SpendText.MenuBarPeriod {
        SpendText.MenuBarPeriod(rawValue: UserDefaults.standard.string(forKey: menuBarPeriodKey) ?? "") ?? .today
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

    /// Every key Kill Cord writes to UserDefaults, for "Remove all local data".
    static let allKeys = [appliedLaunchAtLoginDefaultKey, refreshIntervalKey, menuBarPeriodKey, thresholdsKey,
                          firedAlertsKey, capAuditKey]

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

/// The last spend Kill Cord read, saved so a relaunch can show it (clearly marked not live). Amounts and
/// times only: ~/Library/Application Support/Kill Cord/spend.json.
enum SpendCache {
    static var url: URL { Brand.supportFolder.appendingPathComponent("spend.json") }

    static func load() -> [ProviderState] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ProviderState].self, from: data)) ?? []
    }

    static func save(_ states: [ProviderState]) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        try? FileManager.default.createDirectory(at: Brand.supportFolder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: Brand.supportFolder)
    }
}
