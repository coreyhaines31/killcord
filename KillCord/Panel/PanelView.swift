import KillCordCore
import SwiftUI

/// What opens from the menu bar: totals, a card per connected provider, and the caps audit's progress.
struct PanelView: View {
    let model: SpendModel
    let openSettings: (SettingsWindow.Tab?) -> Void
    let checkForUpdates: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let summary = model.summary(now: context.date)
            VStack(alignment: .leading, spacing: 10) {
                header
                if model.connected.isEmpty {
                    EmptyStateView(connect: { openSettings(.providers) }, reviewCaps: { openSettings(.caps) })
                } else {
                    TotalsView(summary: summary)
                    ForEach(model.connected) { provider in
                        ProviderCard(provider: provider, model: model, now: context.date,
                                     openSettings: openSettings)
                    }
                    capsRow
                }
                footer
            }
            .padding(14)
            .frame(width: 360)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Brand.name).font(.system(size: 15, weight: .semibold))
            if model.isDemo {
                Text("Sample data")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
            }
            Spacer()
            if model.isAsleep || !model.isOnline {
                Text(model.isOnline ? "Paused while asleep" : "Offline, not live")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else if model.isRefreshing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var capsRow: some View {
        let attention = model.capsNeedingAttention
        return Button {
            openSettings(.caps)
        } label: {
            HStack {
                Image(systemName: attention == 0 ? "checkmark.shield" : "exclamationmark.shield")
                    .foregroundStyle(attention == 0 ? Color.green : Color.orange)
                Text(attention == 0 ? "Caps audit: nothing needs attention"
                     : "Caps audit: \(attention) cap\(attention == 1 ? "" : "s") to review")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Button("Refresh") { model.refreshNow() }
                .controlSize(.small)
                .disabled(model.isDemo || model.connected.isEmpty || model.isRefreshing)
            Spacer()
            Menu {
                Button("Settings…") { openSettings(nil) }
                Button("Caps Audit…") { openSettings(.caps) }
                Button("Check for Updates…", action: checkForUpdates)
                Divider()
                Button("Quit \(Brand.name)") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
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
                + "Keys are saved in your Mac's Keychain and never leave your Mac.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Connect a Provider…", action: connect)
                    .buttonStyle(.borderedProminent)
                Button("Review Caps…", action: reviewCaps)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(MoneyText.string(totals) + (summary.stale.isEmpty ? "" : "*"))
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
        }
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
