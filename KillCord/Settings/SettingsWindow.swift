import AppKit
import SwiftUI

/// Standard macOS settings window: icon tabs in the toolbar, sized to each pane.
@MainActor
final class SettingsWindow {
    enum Tab: String, CaseIterable {
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

    static let paneWidth: CGFloat = 560
    /// Providers and Caps Audit have a sidebar, so they open wider.
    static let sidebarPaneWidth: CGFloat = 700

    private let updater: Updater
    private let model: SpendModel
    private let alerts: Alerts
    private var window: NSWindow?

    init(updater: Updater, model: SpendModel, alerts: Alerts) {
        self.updater = updater
        self.model = model
        self.alerts = alerts
    }

    func show(tab: Tab? = nil) {
        if window == nil {
            window = makeWindow()
        }
        if let tab, let tabs = window?.contentViewController as? NSTabViewController,
           let index = tabs.tabViewItems.firstIndex(where: { $0.label == tab.rawValue }) {
            tabs.selectedTabViewItemIndex = index
        }
        alerts.refreshPermission()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        tabs.add(.general, view: GeneralSettingsView(updater: updater, model: model))
        tabs.add(.providers, view: ProvidersSettingsView(model: model) { [weak self] in self?.show(tab: $0) },
                 width: Self.sidebarPaneWidth)
        tabs.add(.thresholds, view: ThresholdsSettingsView(model: model, alerts: alerts))
        tabs.add(.caps, view: CapsAuditView(model: model), width: Self.sidebarPaneWidth)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private final class SettingsTabController: NSTabViewController {
    func add(_ tab: SettingsWindow.Tab, view: some View, width: CGFloat = SettingsWindow.paneWidth) {
        let controller = NSHostingController(rootView: view.frame(width: width))
        controller.sizingOptions = .preferredContentSize
        controller.title = tab.rawValue
        let item = NSTabViewItem(viewController: controller)
        item.label = tab.rawValue
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.rawValue)
        addTabViewItem(item)
    }
}
