import AppKit
import SwiftUI

/// A quiet pointer to the Kill Cord Teams waitlist. The button only opens the page in the default browser:
/// the app sends no request and no identifiers. It doesn't read or change the Teams flag.
struct TeamsWaitlistSection: View {
    static let url = URL(string: "https://killcord.app/teams/?ref=app")!
    static let title = "Kill Cord Teams for companies"
    static let line = "Company API spend, who spent it, and alerts while every Mac is asleep. Join the waitlist."

    var body: some View {
        Section {
            LabeledContent {
                Button("Join Waitlist") { NSWorkspace.shared.open(Self.url) }
            } label: {
                Text(Self.title)
                Text(Self.line)
            }
        }
    }
}
