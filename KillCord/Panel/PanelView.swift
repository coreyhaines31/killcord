import KillCordCore
import PanelKit
import SwiftUI

/// What opens from the menu bar: totals, a card per connected provider, and the caps audit's progress.
struct PanelView: View {
    let model: SpendModel
    let openSettings: (SettingsWindow.Tab?) -> Void
    let checkForUpdates: () -> Void

    @Environment(\.panelTheme) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let summary = model.summary(now: context.date)
            Panel(accent: theme.stop, fillsHeight: true) {
                Fascia(nameplate: "Kill Cord", timestamp: status,
                       detail: model.isDemo ? "Sample data" : "While your Mac is awake",
                       label: "API spend monitor", isLit: model.isOnline && !model.isAsleep) {
                    if !model.connected.isEmpty {
                        TotalsView(summary: summary)
                    }
                }
                .trailingAccessory {
                    KeyCap("arrow.clockwise", accessibilityLabel: "Refresh spend") { model.refreshNow() }
                        .disabled(model.isDemo || model.connected.isEmpty || model.isRefreshing)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.connected.isEmpty {
                            EmptyStateView(connect: { openSettings(.providers) }, reviewCaps: { openSettings(.caps) })
                        } else {
                            ForEach(model.connected) { provider in
                                ProviderCard(provider: provider, model: model, now: context.date,
                                             openSettings: openSettings)
                            }
                            capsRow
                        }
                    }
                }
            } footer: {
                Footer(appName: Brand.name, openSettings: { openSettings(nil) }, quit: { NSApp.terminate(nil) })
            }
            .frame(height: min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 80))
        }
    }

    private var status: String {
        if model.isAsleep { return "Asleep, not live" }
        if !model.isOnline { return "Offline, not live" }
        return model.isRefreshing ? "Checking…" : "Local monitoring"
    }

    private var capsRow: some View {
        let attention = model.capsNeedingAttention
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Native spending caps")
            Button { openSettings(.caps) } label: {
                HStack {
                    StatusLight(attention == 0 ? .go : .caution,
                                attention == 0 ? "Nothing to review" : "\(attention) to review")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            Text("Review provider limits. Kill Cord does not stop spending.")
                .font(PanelFont.body(11))
                .foregroundStyle(theme.sub)
                .padding(.horizontal, 14)
        }
        .padding(.bottom, 14)
    }

}

/// First run: nothing connected yet. Connect is the primary action.
struct EmptyStateView: View {
    let connect: () -> Void
    let reviewCaps: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("See today's and this month's API spend").font(.system(size: 13, weight: .semibold))
            Text("Connect Anthropic, Google Cloud, OpenAI, Vercel, Cloudflare, Twilio, or Neon with a billing key. "
                + "Keys are stored in Keychain and sent only to their provider for authentication.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Connect a Provider…", action: connect)
                    .buttonStyle(.panelPrimary)
                Button("Review Caps…", action: reviewCaps)
                    .buttonStyle(.panelSecondary)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)

    }
}

/// Today and this month across providers, with what the totals leave out said plainly.
struct TotalsView: View {
    let summary: SpendSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                total("Today", summary.today)
                total("This month", summary.month)
                Spacer()
            }
            ForEach(notes, id: \.self) { note in
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func total(_ label: String, _ totals: MoneyTotals) -> some View {
        ReadingTile(label, value: MoneyText.string(totals) + (summary.stale.isEmpty ? "" : "*"))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var notes: [String] {
        var notes: [String] = []
        if !summary.stale.isEmpty {
            notes.append("* Includes numbers that aren't live: " + names(summary.stale) + ".")
        }
        if !summary.missingToday.isEmpty {
            notes.append("Today leaves out " + names(summary.missingToday) + " (not reported yet or not read).")
        }
        if summary.hasEstimates { notes.append("Includes estimates.") }
        notes.append("Each provider's day and month follow its own billing clock.")
        return notes
    }

    private func names(_ providers: [ProviderID]) -> String {
        ListFormatter.localizedString(byJoining: providers.map(\.info.name))
    }
}
