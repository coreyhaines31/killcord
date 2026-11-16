import AppKit
import KillCordCore
import SwiftUI

/// The menu bar plug and the panel it opens.
@MainActor
final class StatusItemController {
    private static let autosaveName = "KillCord"
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let model: SpendModel
    private var hosting: NSHostingController<PanelView>?

    init(model: SpendModel, openSettings: @escaping (SettingsWindow.Tab?) -> Void,
         checkForUpdates: @escaping () -> Void) {
        self.model = model
        // New status items start at the far left on recent macOS, which is off-screen on a crowded menu bar.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position \(Self.autosaveName)": 1])
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)

        let panel = PanelView(model: model, openSettings: { [weak popover] tab in
            popover?.performClose(nil)
            openSettings(tab)
        }, checkForUpdates: checkForUpdates)
        let hosting = NSHostingController(rootView: panel)
        hosting.sizingOptions = .preferredContentSize
        self.hosting = hosting
        popover.contentViewController = hosting
        popover.behavior = .transient
        update()
    }

    func update() {
        let summary = model.summary()
        let period = Preferences.menuBarPeriod
        let crossed = Self.crossesThreshold(summary, period: period)
        item.button?.image = CordGlyph.image(tint: crossed ? .systemOrange : nil)
        let text = SpendText.menuBar(summary, period: period)
        item.button?.title = text.isEmpty ? "" : " " + text
        item.button?.toolTip = toolTip(summary, period: period)
    }

    private func toolTip(_ summary: SpendSummary, period: SpendText.MenuBarPeriod) -> String {
        guard !summary.rows.isEmpty else { return "\(Brand.name): connect a provider to see spend" }
        let totals = period == .today ? summary.today : summary.month
        var text = "\(Brand.name): \(MoneyText.string(totals)) \(period == .today ? "today" : "this month")"
        if !summary.stale.isEmpty { text += ". * Some numbers aren't live." }
        if model.isDemo { text += " (sample data)" }
        return text
    }

    /// Orange when the menu bar's period total is past its total threshold.
    static func crossesThreshold(_ summary: SpendSummary, period: SpendText.MenuBarPeriod) -> Bool {
        let thresholds = Preferences.thresholds.total
        let limit = period == .today ? thresholds.daily : thresholds.monthly
        let total = (period == .today ? summary.today : summary.month).amount(in: .usd)
        guard let limit, let total else { return false }
        return total.amount >= limit
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let button = item.button else { return }
        if let view = hosting?.view {
            popover.contentSize = view.fittingSize
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
