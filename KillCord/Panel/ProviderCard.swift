import AppKit
import KillCordCore
import PanelKit
import SwiftUI

/// One provider: today, this month, when it was last checked, and anything wrong, inline.
struct ProviderCard: View {
    let provider: ProviderID
    let model: SpendModel
    let now: Date
    let openSettings: (SettingsWindow.Tab?) -> Void

    @Environment(\.panelTheme) private var theme

    private var state: ProviderState? { model.states[provider] }
    private var freshness: Freshness { model.freshness(provider, now: now) }
    private var snapshot: SpendSnapshot? { state?.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.info.name).font(PanelFont.condensed(14, .semibold))
                Spacer()
                StatusLight(freshness.isLive ? .go : .caution, freshness.isLive ? "Checked" : "Not live")
            }
            Text(SpendText.freshness(freshness, now: now))
                .font(PanelFont.body(11))
                .foregroundStyle(theme.sub)
            if provider.info.capability.showsMoney {
                money
            } else {
                usage
            }
            if let reason = SpendText.staleReason(freshness) {
                Text(reason).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let asOf = snapshot?.dataAsOf {
                Text("\(provider.info.name) data current through \(SpendText.time(asOf, now: now)).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if provider.info.lag.typical >= 3600 {
                Text(provider.info.lag.note).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = state?.lastError {
                errorRow(error)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.line).frame(height: 1)
        }
    }

    private var money: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            amount("Today", snapshot.map { SpendText.amount($0.today, isEstimate: $0.isEstimate) } ?? "Not read yet")
            amount(snapshot.map { SpendText.monthLabel($0.monthKind, now: now) } ?? "This month",
                   snapshot.map { SpendText.amount($0.month, isEstimate: $0.isEstimate) } ?? "Not read yet")
            Spacer()
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Usage this month (Neon reports usage, not dollars)")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let metrics = snapshot?.usage, !metrics.isEmpty {
                ForEach(metrics) { metric in
                    HStack {
                        Text(metric.name).font(.system(size: 12))
                        Spacer()
                        Text(SpendText.usage(metric)).font(.system(size: 12).monospacedDigit())
                    }
                }
            } else {
                Text("Not read yet").font(.system(size: 12))
            }
        }
    }

    private func amount(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit())
        }
    }

    private func errorRow(_ error: SpendError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(error.message(for: provider), systemImage: "exclamationmark.circle")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            if !error.isTransient {
                Button("Fix in Settings…") { openSettings(.providers) }
                    .buttonStyle(.panelCompact)
            }
        }
    }
}
