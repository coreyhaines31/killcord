import AppKit
import KillCordCore
import PanelKit
import SwiftUI
import XCTest

/// Two accounts of one provider, on sample data: the real Providers sidebar takes one click per account, and
/// the Providers pane and the menu bar panel render offscreen to PNGs for a visual check. Nothing here reads
/// the real app's preferences, Keychain, or spend cache, and Kill Cord itself isn't launched.
@MainActor
final class AccountsTests: XCTestCase {
    private var suiteName = ""
    private var cacheFolder: URL?

    final class Recorder {
        var seen: [ProviderSidebarItem] = []
    }

    struct SidebarHost: View {
        let model: SpendModel
        let recorder: Recorder
        @State var selection: ProviderSidebarItem = .new(.supabase)

        var body: some View {
            ProvidersSidebar(model: model, selection: $selection)
                .frame(width: 230, height: 900)
                .onChange(of: selection) { _, value in recorder.seen.append(value) }
        }
    }

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

    private func demoModel() -> SpendModel {
        let model = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) },
                               isDemo: true)
        model.start()
        return model
    }

    func testOneClickSelectsEachOfTwoAccountsOfOneProvider() throws {
        let model = demoModel()
        let anthropic = model.connections(for: .anthropic).map(\.id)
        XCTAssertEqual(anthropic.count, 2)
        let recorder = Recorder()
        let window = offscreenWindow(SidebarHost(model: model, recorder: recorder), size: NSSize(width: 230, height: 900))
        defer { window.orderOut(nil) }
        for top in stride(from: CGFloat(2), to: 890, by: 4) {
            click(window, x: 80, top: top)
        }
        var distinct: [ProviderSidebarItem] = []
        for item in recorder.seen where distinct.last != item { distinct.append(item) }
        // Every account, top to bottom, then the one provider that isn't connected.
        XCTAssertEqual(distinct, model.connections.map { .connection($0.id) } + [.new(.supabase)])
        XCTAssertEqual(Array(distinct.prefix(2)), anthropic.map { .connection($0) })
    }

    func testRendersTwoAnthropicAccountsInSettingsAndThePanel() throws {
        let model = demoModel()
        let second = try XCTUnwrap(model.connections(for: .anthropic).last)
        let folder = renderFolder()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let pane = ProvidersSettingsView(model: model, selection: .connection(second.id)).frame(width: 700)
            try render(pane, dark: dark, to: folder.appendingPathComponent("providers-two-anthropic-\(suffix).png"))
            let adding = ProvidersSettingsView(model: model, selection: .new(.anthropic)).frame(width: 700)
            try render(adding, dark: dark, to: folder.appendingPathComponent("providers-add-another-\(suffix).png"))
            let panel = PanelView(model: model, openSettings: { _ in }, checkForUpdates: {})
            try render(panel, dark: dark, to: folder.appendingPathComponent("panel-subtotal-\(suffix).png"))
        }
        print("Renders in \(folder.path)")
    }

    func testRendersTheAnthropicSetupSteps() throws {
        // Nothing connected, so Anthropic shows its first-connect steps. In-memory keys, no network.
        let model = SpendModel(secrets: InMemorySecretStore(), http: MockHTTPClient { _ in HTTPResponse(status: 503) })
        model.start()
        XCTAssertTrue(model.connections.isEmpty)
        let folder = renderFolder()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let pane = ProvidersSettingsView(model: model, selection: .new(.anthropic),
                                             editorStart: .init(showsWhy: true)).frame(width: 700)
            try render(pane, dark: dark, to: folder.appendingPathComponent("anthropic-setup-\(suffix).png"))
        }
    }

    // MARK: - Rendering

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
        let window = OffscreenWindow(contentRect: NSRect(x: -20000, y: -20000, width: hosting.frame.width,
                                                         height: hosting.frame.height),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        settle(0.8)
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    // MARK: - Offscreen window and synthetic clicks (as in SidebarPickerTests)

    private func offscreenWindow(_ view: some View, size: NSSize) -> NSWindow {
        let window = OffscreenWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        XCTAssertLessThan(window.frame.origin.x, -10000)
        settle(0.5)
        return window
    }

    private func click(_ window: NSWindow, x: CGFloat, top: CGFloat) {
        let location = NSPoint(x: x, y: window.frame.height - top)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        NSApp.postEvent(event(.leftMouseUp), atStart: false)
        window.sendEvent(event(.leftMouseDown))
        if let mouseUp = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
            window.sendEvent(mouseUp)
        }
        settle(0.03)
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

private final class OffscreenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
}
