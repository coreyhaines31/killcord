import KillCordCore
import PanelKit
import SwiftUI

/// What opens from the menu bar: totals, a card per connection (with a provider subtotal when a provider
/// has more than one), and the caps audit's progress.
struct PanelView: View {
    let model: SpendModel
    let openSettings: (SettingsTab?) -> Void
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
                        TotalsView(summary: summary, hasBalances: model.hasBalances)
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
                            ForEach(summary.groups) { group in
                                if group.rows.count > 1 {
                                    ProviderSubtotal(group: group)
                                }
                                ForEach(group.rows) { row in
                                    ProviderCard(connectionID: row.connectionID, provider: row.provider, name: row.name,
                                                 model: model, now: context.date, openSettings: openSettings)
                                }
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
            Text("Connect Anthropic, Google Cloud, OpenAI, Vercel, Cloudflare, Twilio, or Neon with a billing key, "
                + "or watch a prepaid balance on OpenRouter, DataForSEO, and more. Keys are stored in Keychain and "
                + "sent only to their provider for authentication.")
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
    var hasBalances = false

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
        if hasBalances { notes.append("Balances are what's left, not spend, so they're not in these totals.") }
        notes.append("Each provider's day and month follow its own billing clock.")
        return notes
    }

    private func names(_ ids: [UUID]) -> String {
        ListFormatter.localizedString(byJoining: summary.names(ids))
    }
}

/// Above a provider's cards when it has more than one account: what they add up to.
struct ProviderSubtotal: View {
    let group: SpendSummary.Group

    @Environment(\.panelTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            HStack(spacing: 6) {
                ProviderMark(provider: group.provider, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.provider.info.name).font(PanelFont.condensed(14, .semibold))
                    Text("\(group.rows.count) accounts").font(PanelFont.body(11)).foregroundStyle(theme.sub)
                }
            }
            Spacer()
            if group.provider.info.capability.showsMoney {
                amount("Today", group.today)
                amount("This month", group.month)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.provider.info.name), \(group.rows.count) accounts, today "
            + "\(MoneyText.string(group.today)), this month \(MoneyText.string(group.month))")
    }

    private func amount(_ label: String, _ totals: MoneyTotals) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(MoneyText.string(totals)).font(.system(size: 13, weight: .semibold).monospacedDigit())
        }
    }
}
