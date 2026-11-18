// Kill Cord Teams in the Mac app (docs/product/teams-spec.md, unit 12): sign in, pick a workspace, see your
// own spend. Off by default and with no switch in the app: the free, no-account app behaves exactly as before
// until someone runs `defaults write app.killcord.KillCord teamsEnabled -bool true`. With the flag off, nothing
// here is constructed and the Teams host is never contacted.
import Foundation

public struct TeamsSettings: Sendable, Equatable {
    public static let enabledKey = "teamsEnabled"
    public static let baseURLKey = "teamsBaseURL"
    public static let selectedWorkspaceKey = "teamsSelectedWorkspace"
    /// Not live yet. Development points `teamsBaseURL` at a local server.
    public static let defaultBaseURL = URL(string: "https://app.killcord.app")!

    public var isEnabled: Bool
    public var baseURL: URL

    public init(isEnabled: Bool, baseURL: URL = TeamsSettings.defaultBaseURL) {
        self.isEnabled = isEnabled
        self.baseURL = baseURL
    }

    /// Reads the flag (false when unset) and the base URL override (ignored unless it's safe).
    public static func load(from defaults: UserDefaults) -> TeamsSettings {
        let override = defaults.string(forKey: baseURLKey).flatMap(validBaseURL)
        return TeamsSettings(isEnabled: defaults.bool(forKey: enabledKey), baseURL: override ?? defaultBaseURL)
    }

    /// https anywhere; plain http only for this Mac (local development). No paths, queries or credentials.
    public static func validBaseURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.query == nil,
              url.path.isEmpty || url.path == "/" else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        return nil
    }
}

/// The Mac's device token, kept through the same Keychain abstraction as provider keys. The account name
/// can't collide with a connection's account, which is always a UUID string.
public struct TeamsTokenStore: Sendable {
    public static let account = "app.killcord.teams.device-token"
    private let store: SecretStore

    public init(store: SecretStore) {
        self.store = store
    }

    public func read() -> String? {
        guard let data = try? store.read(account: Self.account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        try store.write(Data(token.utf8), account: Self.account, label: "Kill Cord Teams sign-in")
    }

    public func delete() {
        try? store.delete(account: Self.account)
    }
}
