import AppKit
import KillCordCore
import PanelKit
import SwiftUI
import XCTest

/// The Beta label on a provider not yet verified with a live account: the sidebar, the setup guide, a
/// connected detail with an error, and the panel card, rendered offscreen to PNGs for a visual check. A
/// verified provider renders beside it without the label. Fixture readings on a demo model; no Keychain,
/// network, or real preferences.
@MainActor
final class BetaLabelRenderTests: XCTestCase {
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

    /// Demo data plus one fal connection with a balance and an error from its last check.
    private func betaModel() -> (SpendModel, UUID) {
        let model = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) },
                               isDemo: true)
        model.start()
        let id = UUID(uuidString: "BE7A0000-0000-0000-0000-000000000001")!
        var registry = DemoData.registry()
        registry.insert(ConnectionRecord(id: id, provider: .fal, createdAt: Date(), name: "fal"))
        let state = ProviderState(
            provider: .fal, connectionID: id,
            snapshot: SpendSnapshot(provider: .fal, today: nil, month: nil,
                                    balance: Balance(remaining: Decimal(string: "42.50")!, unit: .money(.usd)),
                                    fetchedAt: Date().addingTimeInterval(-600)),
            lastAttempt: Date(), lastError: .unexpectedResponse)
        model.showSample(registry: registry, states: DemoData.states() + [state])
        return (model, id)
    }

    func testTheBetaReportLineLinksToGitHubIssues() throws {
        let text = BetaReportLine.text
        XCTAssertEqual(String(text.characters), "This provider is in beta. If this looks wrong, report it.")
        let range = try XCTUnwrap(text.range(of: "report it"))
        XCTAssertEqual(text[range].link, URL(string: "https://github.com/coreyhaines31/killcord/issues"))
    }

    func testRendersTheBetaLabel() throws {
        let (model, id) = betaModel()
        XCTAssertTrue(ProviderID.fal.isBeta)
        XCTAssertFalse(ProviderID.anthropic.isBeta)
        let empty = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) })
        empty.start()
        let folder = renderFolder()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let chip = HStack(spacing: 12) {
                BetaChip()
                BetaChip(compact: true)
            }
            .padding(12)
            try render(chip, dark: dark, to: folder.appendingPathComponent("beta-chip-\(suffix).png"))
            let setup = ProvidersSettingsView(model: empty, selection: .new(.fal)).frame(width: 700)
            try render(setup, dark: dark, to: folder.appendingPathComponent("beta-setup-\(suffix).png"))
            let verified = ProvidersSettingsView(model: empty, selection: .new(.anthropic)).frame(width: 700)
            try render(verified, dark: dark, to: folder.appendingPathComponent("beta-verified-setup-\(suffix).png"))
            let connected = ProviderEditor(provider: .fal, connectionID: id, model: model, openTab: { _ in })
                .frame(width: 470, height: 900)
            try render(connected, dark: dark, to: folder.appendingPathComponent("beta-connected-\(suffix).png"))
            let card = ProviderCard(connectionID: id, provider: .fal, name: "fal", model: model, now: Date(),
                                    openSettings: { _ in }).frame(width: 340)
            try render(card, dark: dark, to: folder.appendingPathComponent("beta-card-\(suffix).png"))
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
