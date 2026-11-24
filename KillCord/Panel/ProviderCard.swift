import AppKit
import KillCordCore
import PanelKit
import SwiftUI

/// One connection: today, this month, when it was last checked, and anything wrong, inline.
struct ProviderCard: View {
    let connectionID: UUID
    let provider: ProviderID
    let name: String
    let model: SpendModel
    let now: Date
    let openSettings: (SettingsTab?) -> Void

    @Environment(\.panelTheme) private var theme

    private var state: ProviderState? { model.states[connectionID] }
    private var freshness: Freshness { model.freshness(connectionID, now: now) }
    private var snapshot: SpendSnapshot? { state?.snapshot }
    private var capability: SpendCapability { provider.info.capability }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    ProviderMark(provider: provider, size: 16, serviceName: name)
                    Text(name).font(PanelFont.condensed(14, .semibold))
                    if provider.isBeta { BetaChip(compact: true) }
                }
                Spacer()
                if provider == .manual {
                    StatusLight(.off, "Not live")
                } else {
                    StatusLight(freshness.isLive ? .go : .caution, freshness.isLive ? "Checked" : "Not live")
                }
            }
            if provider == .manual {
                manualRows
            } else {
                readingRows
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.line).frame(height: 1)
        }
    }

    /// A plan the person typed in: never read, never live, never in the totals.
    @ViewBuilder
    private var manualRows: some View {
        Text(ManualText.notLive).font(PanelFont.body(11)).foregroundStyle(theme.sub)
        if let plan = snapshot?.manual {
            amount([plan.plan, ManualText.price(plan)].compactMap { $0 }.joined(separator: ", ").nonEmpty ?? "Plan",
                   ManualText.renewal(plan, now: now))
            if let allowance = ManualText.allowance(plan) {
                Text(allowance).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var readingRows: some View {
        Text(SpendText.freshness(freshness, now: now))
            .font(PanelFont.body(11))
            .foregroundStyle(theme.sub)
        if let balance = snapshot?.balance {
            balanceRow(balance)
        } else if capability.showsBalance {
            amount("Balance", snapshot == nil ? "Not read yet" : "Not reported")
        }
        if capability.showsMoney {
            money
        } else if !capability.showsBalance {
            usage
        }
        if let reason = SpendText.staleReason(freshness) {
            Text(reason).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if provider == .custom {
            Text("From your own setup. Kill Cord can't verify it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
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

    private var money: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            if capability.countsToday {
                amount("Today", snapshot.map { SpendText.amount($0.today, isEstimate: $0.isEstimate) } ?? "Not read yet")
            }
            if capability.countsMonth {
                amount(snapshot.map { SpendText.monthLabel($0.monthKind, now: now) } ?? "This month",
                       snapshot.map { SpendText.amount($0.month, isEstimate: $0.isEstimate) } ?? "Not read yet")
            }
            Spacer()
        }
    }

    /// What's left, with its unit, and anything worth knowing about it. Never mixed into spend.
    private func balanceRow(_ balance: Balance) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            amount(balance.kind == .prepaid ? "Balance" : "Left this period", BalanceText.remaining(balance))
            ForEach(BalanceText.details(balance, now: now), id: \.self) { line in
                Text(line).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            if provider.isBeta { BetaReportLine(fontSize: 11) }
            if !error.isTransient {
                Button("Fix in Settings…") { openSettings(.providers) }
                    .buttonStyle(.panelCompact)
            }
        }
    }
}

extension String {
    /// Nil for an empty string.
    var nonEmpty: String? { isEmpty ? nil : self }
}
