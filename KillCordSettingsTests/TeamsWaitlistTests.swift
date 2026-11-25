import AppKit
import SwiftUI
import XCTest

/// The Teams waitlist row in Settings › General: a plain link to the waitlist page, shown whatever the Teams
/// flag says. Rendered offscreen to PNGs for a visual check; nothing here opens the link or touches the network.
@MainActor
final class TeamsWaitlistTests: XCTestCase {
    func testTheLinkIsThePlainWaitlistPage() throws {
        let url = TeamsWaitlistSection.url
        XCTAssertEqual(url.absoluteString, "https://killcord.app/teams/?ref=app")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items, [URLQueryItem(name: "ref", value: "app")])
    }

    func testTheCopyHasNoEmDashes() {
        XCTAssertFalse(TeamsWaitlistSection.title.contains("\u{2014}"))
        XCTAssertFalse(TeamsWaitlistSection.line.contains("\u{2014}"))
    }

    func testRendersTheWaitlistRow() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let path = ProcessInfo.processInfo.environment["KILLCORD_RENDER_DIR"]
        let folder = path.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("killcord-renders")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dark in [false, true] {
            let form = Form {
                Section {
                    LabeledContent("Version 0.0.0") { Button("Check Now") {} }
                } header: {
                    Text("Updates")
                }
                TeamsWaitlistSection()
            }
            .formStyle(.grouped)
            .frame(width: 560, height: 260)
            try render(form, dark: dark, to: folder.appendingPathComponent("teams-waitlist-\(dark ? "dark" : "light").png"))
        }
        print("Renders in \(folder.path)")
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
