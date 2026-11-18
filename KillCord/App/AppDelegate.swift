import AppKit
import KillCordCore
import PanelKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updater = Updater()
    private var model: SpendModel?
    private var alerts: Alerts?
    private var statusItemController: StatusItemController?
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        PanelFont.register()
        Preferences.registerDefaults()
        #if !DEBUG
        applyLaunchAtLoginDefault()
        #endif
        let model = makeModel()
        self.model = model
        let alerts = Alerts()
        self.alerts = alerts
        let settingsWindow = SettingsWindow(updater: updater, model: model, alerts: alerts)
        self.settingsWindow = settingsWindow
        let statusItemController = StatusItemController(
            model: model,
            openSettings: { settingsWindow.show(tab: $0) },
            checkForUpdates: { [updater] in updater.checkForUpdates() }
        )
        self.statusItemController = statusItemController
        alerts.openPanel = { statusItemController.show() }
        model.onChange = { [weak self] in self?.statusItemController?.update() }
        model.onSpend = { [weak self, weak model] states in
            guard let model, !model.isDemo else { return }
            self?.alerts?.check(states, names: model.registry.names)
        }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItemController?.update() }
        }
        observeSleepAndWake(model)
        model.start()
        #if DEBUG
        if let url = DemoMode.snapshotURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DemoMode.snapshot(model: model, updater: self.updater, alerts: alerts, to: url)
            }
        }
        #endif
    }

    /// The free app polls only while the Mac is awake. On sleep it stops; on wake it checks again, and until
    /// then every reading shows as not live.
    private func observeSleepAndWake(_ model: SpendModel) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.sleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.wake() }
        }
    }

    private func makeModel() -> SpendModel {
        #if DEBUG
        if DemoMode.isOn {
            DemoMode.prepare()
            return SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in
                HTTPResponse(status: 503)
            }, isDemo: true)
        }
        #endif
        return SpendModel()
    }

    /// Turns on launch at login once, so checks resume after a restart. Tries again next launch if it fails.
    /// Debug builds skip it so a DerivedData copy never becomes the login item.
    private func applyLaunchAtLoginDefault() {
        guard !Preferences.appliedLaunchAtLoginDefault else { return }
        guard (try? SMAppService.mainApp.register()) != nil else { return }
        Preferences.appliedLaunchAtLoginDefault = true
    }
}
