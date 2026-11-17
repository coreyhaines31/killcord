import KillCordCore
import PanelKit
import SwiftUI

/// Spend amounts that send a notification: daily and monthly, per provider and in total. Each fires once a
/// day or month.
struct ThresholdsSettingsView: View {
    let model: SpendModel
    let alerts: Alerts
    @State private var thresholds = Preferences.thresholds

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                permissionSection
                Section {
                    columnTitles
                    row(title: "All providers", subtitle: totalSubtitle, mark: nil, limits: $thresholds.total)
                } header: {
                    Text("Total")
                } footer: {
                    Text("Adds up every provider that reports dollars, in USD. The menu bar number turns orange once "
                        + "it passes the total for the period it shows.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    let money = model.connected.filter { $0.info.capability.showsMoney }
                    if money.isEmpty {
                        Text("Connect a provider that reports dollars to give it its own alert.")
                            .foregroundStyle(.secondary)
                    } else {
                        columnTitles
                    }
                    ForEach(money) { provider in
                        row(title: provider.info.name, subtitle: spentToday(provider), mark: provider,
                            limits: Binding(
                                get: { thresholds.perProvider[provider] ?? .init() },
                                set: { thresholds.perProvider[provider] = $0.isEmpty ? nil : $0 }
                            ))
                    }
                } header: {
                    Text("Per provider")
                }
            }
            .formStyle(.grouped)
        }
        .frame(height: 560)
        .onChange(of: thresholds) { _, value in
            Preferences.thresholds = value
            let hasAny = !value.total.isEmpty || value.perProvider.values.contains { !$0.isEmpty }
            if hasAny { alerts.requestPermission() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Spend alerts").font(PanelFont.condensed(22, .semibold)).accessibilityAddTraits(.isHeader)
            Text("Get a notification when spend passes an amount. Each alert fires once a day or month, at the "
                + "first check past it. Leave a box empty for no alert.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Kill Cord can't check while your Mac sleeps. For a hard stop, use each provider's own caps "
                + "in Caps Audit.", systemImage: "moon.zzz")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var permissionSection: some View {
        if alerts.permission == .denied {
            Section {
                ResultBox(light: .caution, title: "Notifications are off for Kill Cord",
                          message: "These alerts can't appear until you allow them.",
                          fix: "Open System Settings › Notifications › Kill Cord and turn on Allow notifications.") {
                    Button("Open Notification Settings") { Alerts.openNotificationSettings() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var columnTitles: some View {
        HStack {
            Spacer()
            Text("Daily").frame(width: AmountField.width, alignment: .leading)
            Text("Monthly").frame(width: AmountField.width, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var totalSubtitle: String? {
        let summary = model.summary()
        guard let today = summary.today.amount(in: .usd) else { return nil }
        return "\(MoneyText.string(today)) so far today"
    }

    private func spentToday(_ provider: ProviderID) -> String? {
        guard let today = model.states[provider]?.snapshot?.today else { return nil }
        return "\(MoneyText.string(today)) so far today"
    }

    private func row(title: String, subtitle: String?, mark: ProviderID?,
                     limits: Binding<SpendThresholds.Limits>) -> some View {
        HStack(spacing: 10) {
            if let mark { ProviderMark(provider: mark) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            AmountField(label: "\(title) daily", value: limits.daily)
            AmountField(label: "\(title) monthly", value: limits.monthly)
        }
    }
}

/// A dollar amount, or empty for none. Parsed as Decimal.
struct AmountField: View {
    static let width: CGFloat = 104

    let label: String
    @Binding var value: Decimal?
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        HStack(spacing: 3) {
            Text("$").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(label, text: $text, prompt: Text("None"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(invalid ? Color.red : Color.primary)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(invalid ? Color.red : .clear))
                .onSubmit(commit)
                .onChange(of: text) { _, _ in commit() }
                .accessibilityLabel("\(label) alert, in dollars")
        }
        .frame(width: Self.width)
        .help(invalid ? "Enter an amount like 25 or 12.50" : "Leave empty for no alert")
        .onAppear {
            text = value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        if trimmed.isEmpty {
            invalid = false
            value = nil
        } else if let amount = Money.decimal(trimmed), amount > 0 {
            invalid = false
            value = amount
        } else {
            invalid = true
        }
    }
}
