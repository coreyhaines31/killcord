import AppKit
import KillCordCore
import SwiftUI
import XCTest

/// Kill Cord Teams in Settings. With the flag off (the default) the Settings window has exactly the free app's
/// tabs; with it on, a "Teams (preview)" tab is added at the end. The pane renders offscreen to PNGs for a
/// visual check. Nothing here launches Kill Cord, reads its preferences or Keychain, or touches the network.
@MainActor
final class TeamsTabTests: XCTestCase {
    /// The free app's Settings tabs before Teams existed, by identifier and order.
    static let freeAppTabs = ["General", "Providers", "Alerts", "Caps Audit"]

    func testWithTeamsOffTheTabsAreExactlyTheFreeAppsTabs() {
        XCTAssertEqual(SettingsTab.visible(teamsEnabled: false).map(\.rawValue), Self.freeAppTabs)
    }

    func testWithTeamsOnTheTeamsTabIsAddedLast() {
        XCTAssertEqual(SettingsTab.visible(teamsEnabled: true).map(\.rawValue), Self.freeAppTabs + ["Teams (preview)"])
    }

    func testTheAppBuildsNoTeamsSessionWhenTheFlagIsUnset() throws {
        let name = "app.killcord.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let http = MockHTTPClient { _ in HTTPResponse(status: 503) }
        XCTAssertNil(TeamsSession.makeIfEnabled(defaults: defaults, http: http, store: InMemorySecretStore()))
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testTheTeamsPaneRendersEachState() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("killcord-renders")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let code = HTTPResponse(status: 200, json: """
            {"device_code":"dev-TEST","user_code":"BCDF-GHJK","verification_uri":"http://localhost:3000/device",
             "verification_uri_complete":"http://localhost:3000/device?code=BCDF-GHJK","expires_in":600,"interval":5}
            """)
        let workspace = "11111111-1111-4111-8111-111111111111"
        let routes: [String: HTTPResponse] = [
            "/devices/start": code,
            "/devices/token": HTTPResponse(status: 200, json: #"{"access_token":"kcd_TEST","token_type":"Bearer"}"#),
            "/me": HTTPResponse(status: 200, json: """
                {"email":"mia@example.test","workspaces":[
                  {"id":"\(workspace)","name":"Acme","role":"member","personal":false}]}
                """),
            "/me/spend": HTTPResponse(status: 200, json: """
                {"month":"2026-11","total":"14.75","units":[{"label":"mia-laptop","how":"assigned","amount":"14.75"}]}
                """)
        ]
        let name = "app.killcord.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = TeamsSettings(isEnabled: true, baseURL: try XCTUnwrap(URL(string: "http://localhost:3000")))
        let client = TeamsClient(baseURL: settings.baseURL, http: MockHTTPClient(routes: routes),
                                 tokens: TeamsTokenStore(store: InMemorySecretStore()))

        // Signed out, then the code (sleep never returns, so it stays on the code), then signed in.
        let waiting = TeamsSession(settings: settings, client: client, defaults: defaults,
                                   sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
        let waitingModel = TeamsModel(session: waiting)
        try render(TeamsSettingsView(model: waitingModel), to: folder.appendingPathComponent("teams-signed-out.png"))
        waitingModel.signIn(deviceName: "Test Mac")
        settle(0.3)
        guard case .showingCode = waitingModel.state else { return XCTFail("expected the code, got \(waitingModel.state)") }
        try render(TeamsSettingsView(model: waitingModel), to: folder.appendingPathComponent("teams-code.png"))
        waitingModel.cancelSignIn()

        let signedIn = TeamsModel(session: TeamsSession(settings: settings, client: client, defaults: defaults,
                                                        sleep: { _ in }))
        signedIn.signIn(deviceName: "Test Mac")
        settle(0.5)
        guard case .signedIn = signedIn.state else { return XCTFail("expected signed in, got \(signedIn.state)") }
        XCTAssertEqual(signedIn.spend?.total, Decimal(string: "14.75", locale: Locale(identifier: "en_US_POSIX")))
        try render(TeamsSettingsView(model: signedIn), to: folder.appendingPathComponent("teams-signed-in.png"))
    }

    private func render(_ view: some View, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.frame(width: 560).background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = TeamsOffscreenWindow(contentRect: NSRect(x: -20000, y: -20000, width: hosting.frame.width,
                                                              height: hosting.frame.height),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.contentView = hosting
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        settle(0.5)
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

private final class TeamsOffscreenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
}
