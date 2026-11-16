import KillCordCore
import SwiftUI

/// Spend amounts that send a notification: daily and monthly, per provider and in total. Each fires once a
/// day or month.
struct ThresholdsSettingsView: View {
    let model: SpendModel
    let alerts: Alerts
    @State private var thresholds = Preferences.thresholds

    var body: some View {
        Form {
            permissionSection
            Section {
                row("All providers", limits: $thresholds.total)
            } header: {
                Text("Total")
            } footer: {
                Text("Adds up every provider that reports dollars, in USD. The menu bar turns orange past the total "
                    + "for the period it shows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                let money = model.connected.filter { $0.info.capability.showsMoney }
                if money.isEmpty {
                    Text("Connect a provider in Providers to set its own alerts.").foregroundStyle(.secondary)
                }
                ForEach(money) { provider in
                    row(provider.info.name, limits: Binding(
                        get: { thresholds.perProvider[provider] ?? .init() },
                        set: { thresholds.perProvider[provider] = $0.isEmpty ? nil : $0 }
                    ))
                }
            } header: {
                Text("Per provider")
            } footer: {
                Text("Alerts can only be as fresh as the last check. Kill Cord doesn't check while your Mac sleeps, "
                    + "so an overnight jump shows up after wake. Your providers' own caps are the real stop; see "
                    + "Caps Audit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
        .onChange(of: thresholds) { _, value in
            Preferences.thresholds = value
            let hasAny = !value.total.isEmpty || value.perProvider.values.contains { !$0.isEmpty }
            if hasAny { alerts.requestPermission() }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if alerts.permission == .denied {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Notifications are off for Kill Cord, so these alerts can't appear.",
                          systemImage: "bell.slash")
                    Text("Open System Settings › Notifications › Kill Cord and turn on Allow notifications.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Open Notification Settings") { Alerts.openNotificationSettings() }
                }
            }
        }
    }

    private func row(_ title: String, limits: Binding<SpendThresholds.Limits>) -> some View {
        LabeledContent(title) {
            HStack {
                AmountField(label: "Daily", value: limits.daily)
                AmountField(label: "Monthly", value: limits.monthly)
            }
        }
    }
}

/// A dollar amount, or empty for none. Parsed as Decimal.
struct AmountField: View {
    let label: String
    @Binding var value: Decimal?
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        HStack(spacing: 4) {
            Text("$").foregroundStyle(.secondary)
            TextField(label, text: $text, prompt: Text(label))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .foregroundStyle(invalid ? Color.red : Color.primary)
                .onSubmit(commit)
                .onChange(of: text) { _, _ in commit() }
        }
        .help(invalid ? "Enter an amount like 25 or 12.50" : "\(label) alert in USD; leave empty for none")
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
