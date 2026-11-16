import Foundation

public enum Brand {
    public static let name = "Kill Cord"
    public static let bundleIdentifier = "app.killcord.KillCord"
    public static let repository = "https://github.com/coreyhaines31/killcord"

    /// The Keychain service every provider key is saved under. One item per provider, the account is the
    /// provider's id. Uninstall instructions name this, so keep it stable.
    public static let keychainService = "app.killcord.KillCord.providers"

    /// Where the app keeps non-secret state (last spend readings, audit marks):
    /// ~/Library/Application Support/Kill Cord. Never keys.
    public static var supportFolder: URL {
        if let override = ProcessInfo.processInfo.environment["KILLCORD_HOME"] {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(name, isDirectory: true)
    }
}
