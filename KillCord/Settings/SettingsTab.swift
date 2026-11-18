/// The Settings window's tabs. Its own file so offscreen tests can compile the panes without the window.
enum SettingsTab: String, CaseIterable {
    case general = "General"
    case providers = "Providers"
    case thresholds = "Alerts"
    case caps = "Caps Audit"
    /// Kill Cord Teams, only when the `teamsEnabled` flag is on (off by default, no switch in the app).
    case teams = "Teams (preview)"

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .providers: "key"
        case .thresholds: "bell"
        case .caps: "checkmark.shield"
        case .teams: "person.2"
        }
    }

    /// The tabs to show. With Teams off, exactly the free app's tabs, in their usual order.
    static func visible(teamsEnabled: Bool) -> [SettingsTab] {
        allCases.filter { $0 != .teams || teamsEnabled }
    }
}
