#if DEBUG
import AppKit
import KillCordCore
import SwiftUI

/// Runs the app on sample spend, for screenshots and visual checks. Debug builds only. The panel says
/// "Sample data" whenever this is on.
///
///     --demo                    sample data; no Keychain, no network
///     --snapshot <file.png>     draw the panel and each settings pane to PNGs and quit
///     --dark                    dark appearance
@MainActor
enum DemoMode {
    nonisolated static let isOn = CommandLine.arguments.contains("--demo")

    static var snapshotURL: URL? {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }

    static func prepare() {
        NSApp.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
    }

    /// Draws the panel and settings panes offscreen and saves them. An app can always draw its own views, so
    /// this needs no Screen Recording permission.
    static func snapshot(model: SpendModel, updater: Updater, alerts: Alerts, to url: URL) {
        let panes: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettingsView(updater: updater, model: model))),
            ("providers", AnyView(ProvidersSettingsView(model: model))),
            ("thresholds", AnyView(ThresholdsSettingsView(model: model, alerts: alerts))),
            ("caps", AnyView(CapsAuditView(model: model)))
        ]
        for (name, pane) in panes {
            let paneURL = url.deletingPathExtension().appendingPathExtension("\(name).png")
            render(pane.frame(width: SettingsWindow.paneWidth), to: paneURL)
        }
        render(PanelView(model: model, openSettings: { _ in }, checkForUpdates: {}), to: url) {
            NSApp.terminate(nil)
        }
    }

    private static func render(_ view: some View, to url: URL, then done: (() -> Void)? = nil) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(
            contentRect: NSRect(x: -5000, y: -5000, width: hosting.frame.width, height: hosting.frame.height),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            window.orderOut(nil)
            done?()
        }
    }
}
#endif
