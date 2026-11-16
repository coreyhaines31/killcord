import Foundation
import Sparkle

/// Sparkle auto-updates, fed from the appcast attached to each GitHub release.
@MainActor
final class Updater {
    static var isConfigured: Bool {
        #if DEBUG
        if DemoMode.isOn { return false }
        #endif
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && !key.hasPrefix("REPLACE_WITH")
    }

    private let controller = SPUStandardUpdaterController(
        startingUpdater: Updater.isConfigured,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var canCheck: Bool { Self.isConfigured && controller.updater.canCheckForUpdates }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        guard Self.isConfigured else { return }
        controller.checkForUpdates(nil)
    }
}
