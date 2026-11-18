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

    func testRendersTheBalanceProvidersFromDemoDataAndTheirSetup() throws {
        let model = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) },
                               isDemo: true)
        model.start()
        let dataforseo = try XCTUnwrap(model.connections(for: .dataforseo).first)
        let firecrawl = try XCTUnwrap(model.connections(for: .firecrawl).first)
        XCTAssertEqual(model.status(dataforseo.id).line, "Connected · $41.25 left")
        // Nothing connected for the setup screens. In-memory keys, no network.
        let empty = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) })
        empty.start()
        let folder = renderFolder()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for (record, name) in [(dataforseo, "dataforseo"), (firecrawl, "firecrawl")] {
                let card = ProviderCard(connectionID: record.id, provider: record.provider, name: record.name,
                                        model: model, now: Date(), openSettings: { _ in }).frame(width: 340)
                try render(card, dark: dark, to: folder.appendingPathComponent("\(name)-card-\(suffix).png"))
            }
            let pane = ProvidersSettingsView(model: model, selection: .connection(firecrawl.id)).frame(width: 700)
            try render(pane, dark: dark, to: folder.appendingPathComponent("firecrawl-settings-\(suffix).png"))
            for provider in [ProviderID.dataforseo, .treg, .openrouter] {
                let setup = ProvidersSettingsView(model: empty, selection: .new(provider),
                                                  editorStart: .init(showsWhy: true)).frame(width: 700)
                try render(setup, dark: dark, to: folder.appendingPathComponent("\(provider.rawValue)-setup-\(suffix).png"))
            }
        }
    }

    func testRendersACustomConnectionSetupAndReading() throws {
        let empty = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) })
        empty.start()
        let model = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) },
                               isDemo: true)
        model.start()
        let id = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
        var registry = DemoData.registry()
        registry.insert(ConnectionRecord(id: id, provider: .custom, createdAt: Date(), name: "ScrapeCreators"))
        let state = ProviderState(provider: .custom, connectionID: id, snapshot: SpendSnapshot(
            provider: .custom, today: nil, month: nil,
            balance: Balance(remaining: 18_250, unit: .units("credits")), fetchedAt: Date().addingTimeInterval(-300)))
        model.showSample(registry: registry, states: DemoData.states() + [state])
        let folder = renderFolder()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            // The editor alone and tall, so the whole form shows; in Settings it scrolls.
            let setup = ProviderEditor(provider: .custom, connectionID: nil, model: empty, openTab: { _ in })
                .frame(width: 470, height: 2300)
            try render(setup, dark: dark, to: folder.appendingPathComponent("custom-setup-\(suffix).png"))
            let card = ProviderCard(connectionID: id, provider: .custom, name: "ScrapeCreators", model: model,
                                    now: Date(), openSettings: { _ in }).frame(width: 340)
            try render(card, dark: dark, to: folder.appendingPathComponent("custom-card-\(suffix).png"))
            let pane = ProvidersSettingsView(model: model, selection: .connection(id)).frame(width: 700)
            try render(pane, dark: dark, to: folder.appendingPathComponent("custom-settings-\(suffix).png"))
        }
    }

    func testRendersAManualEntry() throws {
        let model = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) },
                               isDemo: true)
        model.start()
        let manual = try XCTUnwrap(model.connections(for: .manual).first)
        XCTAssertEqual(model.status(manual.id).label, "Entered by you")
        let empty = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) })
        empty.start()
        let folder = renderFolder()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let card = ProviderCard(connectionID: manual.id, provider: .manual, name: manual.name, model: model,
                                    now: Date(), openSettings: { _ in }).frame(width: 340)
            try render(card, dark: dark, to: folder.appendingPathComponent("manual-card-\(suffix).png"))
            let pane = ProvidersSettingsView(model: model, selection: .connection(manual.id)).frame(width: 700)
            try render(pane, dark: dark, to: folder.appendingPathComponent("manual-settings-\(suffix).png"))
            let setup = ProviderEditor(provider: .manual, connectionID: nil, model: empty, openTab: { _ in })
                .frame(width: 470, height: 1500)
            try render(setup, dark: dark, to: folder.appendingPathComponent("manual-setup-\(suffix).png"))
        }
    }

    /// Every provider's mark on its key, at the sidebar and header sizes, to compare the new ones with the rest.
    func testRendersEveryMark() throws {
        let sheet = VStack(alignment: .leading, spacing: 10) {
            ForEach(ProviderID.allCases) { provider in
                HStack(spacing: 12) {
                    ProviderMark(provider: provider, size: 16)
                    ProviderMark(provider: provider, size: 22)
                    ProviderMark(provider: provider, size: 34)
                    Text(provider.info.name)
                }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        let folder = renderFolder()
        for dark in [false, true] {
            try render(sheet, dark: dark, to: folder.appendingPathComponent("marks-\(dark ? "dark" : "light").png"))
        }
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
