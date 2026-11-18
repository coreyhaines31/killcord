import AppKit
import KillCordCore
import PanelKit
import SwiftUI

/// Today and this month (or usage), when it was read, and how far behind the provider runs.
struct SpendReadout: View {
    let connectionID: UUID
    let provider: ProviderID
    let model: SpendModel

    var body: some View {
        let now = Date()
        let snapshot = model.states[connectionID]?.snapshot
        let freshness = model.freshness(connectionID, now: now)
        let capability = provider.info.capability
        if provider == .manual {
            manual(snapshot?.manual, now: now)
        } else {
            reading(snapshot: snapshot, freshness: freshness, capability: capability, now: now)
        }
    }

    /// A plan the person typed in. Says plainly it isn't live.
    private func manual(_ plan: ManualPlan?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 32) {
                figure(plan?.plan ?? "Plan", plan.flatMap(ManualText.price) ?? "No price entered")
                figure("Next renewal", plan.map { ManualText.renewalDay($0, now: now) })
                Spacer()
            }
            if let allowance = plan.flatMap(ManualText.allowance) {
                Text(allowance + ".").font(.callout)
            }
            Text(ManualText.notLive + ". Kill Cord never contacts the service, and this isn't in your totals.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func reading(snapshot: SpendSnapshot?, freshness: Freshness, capability: SpendCapability,
                         now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let balance = snapshot?.balance {
                VStack(alignment: .leading, spacing: 4) {
                    figure(balance.kind == .prepaid ? "Balance" : "Left this period", BalanceText.remaining(balance))
                    ForEach(BalanceText.details(balance, now: now), id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("A balance is what's left, not spend, so it isn't in your totals.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if capability.showsBalance {
                figure("Balance", snapshot == nil ? nil : "Not reported")
            }
            if capability.showsMoney {
                HStack(alignment: .firstTextBaseline, spacing: 32) {
                    if capability.countsToday {
                        figure("Today", snapshot.map { SpendText.amount($0.today, isEstimate: $0.isEstimate) })
                    }
                    if capability.countsMonth {
                        figure(snapshot.map { SpendText.monthLabel($0.monthKind, now: now) } ?? "This month",
                               snapshot.map { SpendText.amount($0.month, isEstimate: $0.isEstimate) })
                    }
                    Spacer()
                }
            } else if capability.showsBalance {
                EmptyView()
            } else if let metrics = snapshot?.usage, !metrics.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 32) {
                    ForEach(metrics) { figure($0.name + " this month", SpendText.usage($0)) }
                    Spacer()
                }
            } else {
                figure("Usage this month", nil)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(freshnessLine(freshness, snapshot: snapshot, now: now)).font(.callout)
                if let reason = SpendText.staleReason(freshness) {
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                }
                // Slow providers get the full note; the header already says the delay for the rest.
                if provider.info.lag.typical >= 3600 {
                    Text(provider.info.lag.note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func freshnessLine(_ freshness: Freshness, snapshot: SpendSnapshot?, now: Date) -> String {
        if model.inFlight.contains(connectionID), snapshot == nil { return "Reading spend now…" }
        let line = SpendText.freshness(freshness, now: now)
        guard let asOf = snapshot?.dataAsOf else { return line }
        return "\(line). Data current through \(SpendText.time(asOf, now: now))."
    }

    private func figure(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "Not read yet")
                .font(value == nil ? .callout : .system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// This provider's native caps as a checklist, with a way into Caps Audit.
struct CapsSummarySection: View {
    let provider: ProviderID
    let model: SpendModel
    let openTab: @MainActor (SettingsTab) -> Void

    var body: some View {
        let now = Date()
        let progress = model.audit.progress(for: provider, now: now)
        if !CapsCatalog.controls(for: provider).isEmpty {
            Section {
                ForEach(CapsCatalog.controls(for: provider)) { control in
                    let status = model.audit.status(of: control, now: now)
                    HStack(spacing: 8) {
                        StatusLED(status.light.panel)
                        Text(control.name)
                        Spacer()
                        Text(status.label).font(.callout).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                HStack {
                    Text("Spend caps")
                    Spacer()
                    Button("Open Caps Audit") { openTab(.caps) }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            } footer: {
                Text("\(progress.done) of \(progress.total) done. The provider's own caps are what stop a runaway bill.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The fields a provider needs, with a Paste button beside each secret.
struct CredentialFields: View {
    let fields: [CredentialField]
    @Binding var values: [String: String]
    let keepsSavedSecrets: Bool
    let isDisabled: Bool
    /// True after a connect attempt failed. A custom setup whose problem is in an advanced field opens them.
    var failed = false
    var provider: ProviderID?
    @State private var showsAdvanced = false

    private var advanced: [CredentialField] { fields.filter(\.isAdvanced) }

    /// Something typed (or saved) in a field that's tucked away, so it's never hidden from the person.
    private var advancedHasValues: Bool {
        advanced.contains { !(values[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(fields.filter { !$0.isAdvanced }) { field in
                row(field)
            }
            if !advanced.isEmpty {
                DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(advanced) { field in
                            row(field)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.callout.weight(.medium))
            }
        }
        .disabled(isDisabled)
        .onAppear {
            if advancedHasValues { showsAdvanced = true }
            openForProblem()
        }
        .onChange(of: advancedHasValues) { _, filled in if filled { showsAdvanced = true } }
        .onChange(of: failed) { _, _ in openForProblem() }
    }

    /// After a failed test, opens Advanced when the field at fault is in it.
    private func openForProblem() {
        guard failed, provider == .custom else { return }
        let field = CustomConfig.fieldWithProblem(ProviderCredentials(provider: .custom, values: values))
        if advanced.contains(where: { $0.id == field }) { showsAdvanced = true }
    }

    /// A field with fixed choices. Shows the first until one is picked.
    private func picker(_ field: CredentialField) -> some View {
        Picker(field.label, selection: Binding(get: { values[field.id] ?? field.choices[0] },
                                               set: { values[field.id] = $0 })) {
            ForEach(field.choices, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private func row(_ field: CredentialField) -> some View {
        let binding = Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0 })
        let placeholder = field.isSecret && keepsSavedSecrets ? "Leave empty to keep the saved one" : field.placeholder
        return VStack(alignment: .leading, spacing: 4) {
            Text(field.label + (field.isOptional && field.choices.isEmpty ? " (optional)" : ""))
                .font(.callout.weight(.medium))
            HStack(alignment: .top, spacing: 6) {
                if !field.choices.isEmpty {
                    picker(field)
                } else if field.isMultiline {
                    // A JSON key file. Never shown again once saved.
                    TextEditor(text: binding)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 64)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.35)))
                        .overlay(alignment: .topLeading) {
                            if binding.wrappedValue.isEmpty {
                                Text(placeholder).font(.system(size: 11)).foregroundStyle(.tertiary)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel(field.label)
                } else if field.isSecret {
                    SecureField(field.label, text: binding, prompt: Text(placeholder))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                } else {
                    TextField(field.label, text: binding, prompt: Text(placeholder))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
                if field.isSecret {
                    Button("Paste") {
                        if let text = NSPasteboard.general.string(forType: .string) { binding.wrappedValue = text }
                    }
                    .help("Paste from the clipboard")
                    .accessibilityLabel("Paste \(field.label)")
                }
            }
            if !field.help.isEmpty {
                Text(field.help).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
