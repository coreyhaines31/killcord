import AppKit
import SwiftUI
import XCTest

/// Clicks the Settings sidebar with synthetic mouse events in a window that stays 20,000 points off the
/// screen, fully transparent, in a process that never activates. Kill Cord itself isn't launched.
@MainActor
final class SidebarPickerTests: XCTestCase {
    /// Identified by a String, like `ProviderID`, which is what broke `List(selection:)`.
    enum Fruit: String, CaseIterable, Identifiable {
        case apple, banana, cherry, date
        var id: String { rawValue }
    }

    final class Recorder {
        var seen: [Fruit] = []
    }

    struct Host: View {
        let recorder: Recorder
        @State var selection: Fruit = .date

        var body: some View {
            SidebarPicker(groups: [.init(title: "Fruit", items: Fruit.allCases)], selection: $selection) {
                Text($0.rawValue)
            }
            .frame(width: 200, height: 260)
            .onChange(of: selection) { _, value in recorder.seen.append(value) }
        }
    }

    override func setUp() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    func testOneClickSelectsEachRowInOrder() {
        let recorder = Recorder()
        let window = offscreenWindow(Host(recorder: recorder), size: NSSize(width: 200, height: 260))
        defer { window.orderOut(nil) }
        // Click down the sidebar every few points; each row should be selected once, top to bottom.
        for top in stride(from: CGFloat(2), to: 250, by: 4) {
            click(window, x: 60, top: top)
        }
        var distinct: [Fruit] = []
        for fruit in recorder.seen where distinct.last != fruit { distinct.append(fruit) }
        XCTAssertEqual(distinct, Fruit.allCases)
    }

    func testArrowKeysMoveTheSelection() {
        let recorder = Recorder()
        let window = offscreenWindow(Host(recorder: recorder), size: NSSize(width: 200, height: 260), keyable: true)
        defer { window.orderOut(nil) }
        // Select the first row, then press the down arrow twice.
        for top in stride(from: CGFloat(2), to: 250, by: 4) where recorder.seen.isEmpty {
            click(window, x: 60, top: top)
        }
        XCTAssertEqual(recorder.seen.last, .apple)
        for _ in 0..<2 { press(window, keyCode: 125, character: NSDownArrowFunctionKey) }
        XCTAssertEqual(recorder.seen.last, .cherry)
    }

    // MARK: - Offscreen window and synthetic events

    private func offscreenWindow(_ view: some View, size: NSSize, keyable: Bool = false) -> NSWindow {
        // Mouse events only reach windows that are ordered in. Borderless windows aren't pulled back onto a
        // screen, so this one stays far away, invisible, behind everything.
        let window = OffscreenWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        window.keyable = keyable
        window.alphaValue = 0
        window.contentView = NSHostingView(rootView: view)
        window.orderBack(nil)
        // Key only within this process, which never activates, so no keystroke from the real keyboard lands here.
        if keyable { window.makeKey() }
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
        settle(0.05)
    }

    private func press(_ window: NSWindow, keyCode: UInt16, character: Int) {
        let text = String(Character(UnicodeScalar(character)!))
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, characters: text, charactersIgnoringModifiers: text,
                                    isARepeat: false, keyCode: keyCode)!
        window.sendEvent(down)
        settle(0.1)
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

private final class OffscreenWindow: NSWindow {
    var keyable = false
    override var canBecomeKey: Bool { keyable }
}
