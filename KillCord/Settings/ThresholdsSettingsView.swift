import KillCordCore
import PanelKit
import SwiftUI

/// Spend amounts that send a notification: daily and monthly, per account, per provider across its
/// accounts, and in total. Each fires once a day or month.
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
                let money = model.connected.filter { $0.info.capability.showsMoney }
                if money.isEmpty {
                    Section("Per account") {
                        Text("Connect a provider that reports dollars to give it its own alert.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(money) { provider in
                    providerSection(provider)
                }
                lowBalanceSection
            }
            .formStyle(.grouped)
        }
        .frame(height: 560)
        // The tab stays alive while Settings is open; removing an account drops its limits from Preferences.
        .onAppear { thresholds = Preferences.thresholds }
        .onChange(of: thresholds) { _, value in
            Preferences.thresholds = value
            if !value.isEmpty { alerts.requestPermission() }
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

    /// One provider's accounts, each with its own alert, and with more than one, an alert for all of them.
    private func providerSection(_ provider: ProviderID) -> some View {
        let records = model.connections(for: provider)
        let showsTotal = records.count > 1 || !(thresholds.providerTotals[provider]?.isEmpty ?? true)
        return Section {
            columnTitles
            if showsTotal {
                row(title: "All \(provider.info.name) accounts", subtitle: providerToday(provider), mark: provider,
                    limits: Binding(
                        get: { thresholds.providerTotals[provider] ?? .init() },
                        set: { thresholds.providerTotals[provider] = $0.isEmpty ? nil : $0 }
                    ))
            }
            ForEach(records) { record in
                row(title: record.name, subtitle: spentToday(record.id), mark: showsTotal ? nil : provider,
                    limits: Binding(
                        get: { thresholds.perConnection[record.id] ?? .init() },
                        set: { thresholds.perConnection[record.id] = $0.isEmpty ? nil : $0 }
                    ))
                    .padding(.leading, showsTotal ? 26 : 0)
            }
        } header: {
            Text(records.count > 1 ? "\(provider.info.name) accounts" : provider.info.name)
        }
    }

    /// One alert per connection with a balance, in that balance's own unit. Fires once each time it drops
    /// to the amount, and again only after it's been topped up or reset.
    @ViewBuilder
    private var lowBalanceSection: some View {
        let records = model.balanceConnections
        if !records.isEmpty {
            Section {
                ForEach(records) { record in
                    let balance = model.states[record.id]?.snapshot?.balance
                    HStack(spacing: 10) {
                        ProviderMark(provider: record.provider)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.name)
                            Text(balance.map(BalanceText.remaining) ?? "Not read yet")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        AmountField(label: "\(record.name) low balance", unit: balance?.unit ?? .money(.usd),
                                    value: Binding(
                                        get: { thresholds.perConnection[record.id]?.lowBalance },
                                        set: { value in
                                            var limits = thresholds.perConnection[record.id] ?? .init()
                                            limits.lowBalance = value
                                            thresholds.perConnection[record.id] = limits.isEmpty ? nil : limits
                                        }
                                    ))
                    }
                }
            } header: {
                Text("Low balance")
            } footer: {
                Text("Alerts when a balance is at or below the amount, in its own unit. It alerts again only after "
                    + "a top-up or reset. Balances aren't spend, so they're not in the totals above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func spentToday(_ id: UUID) -> String? {
        guard let today = model.states[id]?.snapshot?.today else { return nil }
        return "\(MoneyText.string(today)) so far today"
    }

    private func providerToday(_ provider: ProviderID) -> String? {
        guard let group = model.summary().groups.first(where: { $0.provider == provider }),
              let today = group.today.amount(in: .usd) else { return nil }
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
    /// Dollars unless a balance is in credits or other units.
    var unit: Balance.Unit = .money(.usd)
    @Binding var value: Decimal?
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        HStack(spacing: 3) {
            if unit == .money(.usd) {
                Text("$").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            TextField(label, text: $text, prompt: Text("None"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(invalid ? Color.red : Color.primary)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(invalid ? Color.red : .clear))
                .onSubmit(commit)
                .onChange(of: text) { _, _ in commit() }
                .accessibilityLabel("\(label) alert, in \(unitWord)")
            if case .units(let name) = unit {
                Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1).accessibilityHidden(true)
            } else if case .money(let currency) = unit, currency != .usd {
                Text(currency.code).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .frame(width: unit == .money(.usd) ? Self.width : Self.width + 56)
        .help(invalid ? "Enter an amount like 25 or 12.50" : "Leave empty for no alert")
        .onAppear {
            text = value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        }
    }

    private var unitWord: String {
        switch unit {
        case .money(let currency): currency == .usd ? "dollars" : currency.code
        case .units(let name): name
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
