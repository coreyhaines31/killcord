import AppKit
import KillCordCore
import PanelKit
import SwiftUI
import XCTest

/// A balance on a connection, rendered offscreen to PNGs for a visual check: the panel card and the Settings
/// readout. Fixture readings on a demo model; no Keychain, network, or real preferences.
@MainActor
final class BalanceRenderTests: XCTestCase {
    private var suiteName = ""
    private var cacheFolder: URL?

    override func setUp() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        PanelFont.register()
        suiteName = "app.killcord.tests.\(UUID().uuidString)"
        Preferences.defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        cacheFolder = folder
        SpendCache.folder = folder
    }

    override func tearDown() async throws {
        Preferences.defaults.removePersistentDomain(forName: suiteName)
        Preferences.defaults = .standard
        if let cacheFolder { try? FileManager.default.removeItem(at: cacheFolder) }
    }

    /// Demo data plus one connection carrying a credit allowance.
    func balanceModel(_ balance: Balance) -> (SpendModel, UUID) {
        let model = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) },
                               isDemo: true)
        model.start()
        let id = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
        var registry = DemoData.registry()
        registry.insert(ConnectionRecord(id: id, provider: .openai, createdAt: Date(), name: "Prepaid credits"))
        let state = ProviderState(provider: .openai, connectionID: id, snapshot: SpendSnapshot(
            provider: .openai, today: Money(Decimal(string: "1.20")!), month: Money(Decimal(string: "9.80")!),
            balance: balance, fetchedAt: Date().addingTimeInterval(-120)))
        model.showSample(registry: registry, states: DemoData.states() + [state])
        return (model, id)
    }

    func testRendersABalanceInThePanelAndSettings() throws {
        let credits = Balance(remaining: 8200, unit: .units("credits"), kind: .allowance, limit: 10000, used: 1800,
                              dollarsPerUnit: Decimal(string: "0.01"), resetsAt: Date().addingTimeInterval(9 * 86400))
        let (model, id) = balanceModel(credits)
        XCTAssertTrue(model.hasBalances)
        XCTAssertEqual(model.status(id).line, "Connected · 8,200 credits left")
        let folder = renderFolder()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let panel = PanelView(model: model, openSettings: { _ in }, checkForUpdates: {})
            try render(panel, dark: dark, to: folder.appendingPathComponent("balance-panel-\(suffix).png"))
            // The card on its own: in the full panel it sits below the fold.
            let card = ProviderCard(connectionID: id, provider: .openai, name: "Prepaid credits", model: model,
                                    now: Date(), openSettings: { _ in }).frame(width: 340)
            try render(card, dark: dark, to: folder.appendingPathComponent("balance-card-\(suffix).png"))
            let pane = ProvidersSettingsView(model: model, selection: .connection(id)).frame(width: 700)
            try render(pane, dark: dark, to: folder.appendingPathComponent("balance-settings-\(suffix).png"))
        }
        print("Renders in \(folder.path)")
    }

    // MARK: - Rendering (as in AccountsTests)

    private func renderFolder() -> URL {
        let path = ProcessInfo.processInfo.environment["KILLCORD_RENDER_DIR"]
        let folder = path.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("killcord-renders")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func render(_ view: some View, dark: Bool, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: hosting.frame.width,
                                                  height: hosting.frame.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
