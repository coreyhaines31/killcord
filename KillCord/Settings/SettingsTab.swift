/// The Settings window's tabs. Its own file so offscreen tests can compile the panes without the window.
enum SettingsTab: String, CaseIterable {
    case general = "General"
    case providers = "Providers"
    case thresholds = "Alerts"
    case caps = "Caps Audit"

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .providers: "key"
        case .thresholds: "bell"
        case .caps: "checkmark.shield"
        }
    }
}
