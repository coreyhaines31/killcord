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
        VStack(alignment: .leading, spacing: 10) {
            if provider.info.capability.showsMoney {
                HStack(alignment: .firstTextBaseline, spacing: 32) {
                    figure("Today", snapshot.map { SpendText.amount($0.today, isEstimate: $0.isEstimate) })
                    figure(snapshot.map { SpendText.monthLabel($0.monthKind, now: now) } ?? "This month",
                           snapshot.map { SpendText.amount($0.month, isEstimate: $0.isEstimate) })
                    Spacer()
                }
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

/// The fields a provider needs, with a Paste button beside each secret.
struct CredentialFields: View {
    let fields: [CredentialField]
    @Binding var values: [String: String]
    let keepsSavedSecrets: Bool
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(fields) { field in
                row(field)
            }
        }
        .disabled(isDisabled)
    }

    private func row(_ field: CredentialField) -> some View {
        let binding = Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0 })
        let placeholder = field.isSecret && keepsSavedSecrets ? "Leave empty to keep the saved one" : field.placeholder
        return VStack(alignment: .leading, spacing: 4) {
            Text(field.label + (field.isOptional ? " (optional)" : "")).font(.callout.weight(.medium))
            HStack(alignment: .top, spacing: 6) {
                if field.isMultiline {
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
