import AppKit
import KillCordCore
import Observation
import UserNotifications

/// Posts the threshold notifications `ThresholdPlanner` decides on, and keeps what already fired across
/// launches. Tracks notification permission so Settings can say, inline, when alerts can't be shown.
@MainActor
@Observable
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    enum Permission: Equatable {
        case unknown
        case notAsked
        case allowed
        case denied
    }

    private(set) var permission: Permission = .unknown
    @ObservationIgnored private var state = Preferences.firedAlerts
    private let center = UNUserNotificationCenter.current()
    @ObservationIgnored var openPanel: () -> Void = {}

    override init() {
        super.init()
        center.delegate = self
        refreshPermission()
    }

    func refreshPermission() {
        // @Sendable: UserNotifications calls this on a background queue, so it mustn't inherit the main actor.
        center.getNotificationSettings { @Sendable settings in
            let permission: Permission = switch settings.authorizationStatus {
            case .notDetermined: .notAsked
            case .denied: .denied
            default: .allowed
            }
            Task { @MainActor in self.permission = permission }
        }
    }

    /// Asked when the first threshold is set, not at launch.
    func requestPermission() {
        guard permission == .notAsked || permission == .unknown else { return }
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in
            Task { @MainActor in self.refreshPermission() }
        }
    }

    func check(_ states: [ProviderState], now: Date = Date()) {
        let (alerts, next) = ThresholdPlanner().plan(states: states, thresholds: Preferences.thresholds,
                                                     state: state, now: now)
        state = next
        Preferences.firedAlerts = next
        alerts.forEach(post)
    }

    private func post(_ alert: ThresholdPlanner.Alert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
    }

    /// Opens System Settings at Notifications, for the inline "turn them on" guidance.
    static func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { openPanel() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
