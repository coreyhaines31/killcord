import AppKit
import KillCordCore
import SwiftUI

/// The guided native-caps audit: for each provider, the spend controls it offers, whether each stops spend
/// or only alerts, a link to the exact console page, and a checklist. Kill Cord never changes a cap itself.
struct CapsAuditView: View {
    let model: SpendModel
    @State private var selection: ProviderID = .anthropic

    var body: some View {
        HStack(spacing: 0) {
            List(ProviderID.allCases, selection: $selection) { provider in
                HStack {
                    Text(provider.info.name)
                    Spacer()
                    progress(provider)
                }
                .tag(provider)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            ProviderCapsView(provider: selection, model: model)
                .id(selection)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 560)
        .onAppear {
            if let first = model.auditProviders.first(where: {
                model.audit.progress(for: $0, now: Date()).needsAttention > 0
            }) {
                selection = first
            }
        }
    }

    private func progress(_ provider: ProviderID) -> some View {
        let progress = model.audit.progress(for: provider, now: Date())
        return Text("\(progress.done)/\(progress.total)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(progress.isComplete ? Color.green : Color.secondary)
    }
}

struct ProviderCapsView: View {
    let provider: ProviderID
    let model: SpendModel
    @State private var checking = false

    private var canCheck: Bool {
        model.connected.contains(provider)
            && CapsCatalog.controls(for: provider).contains { $0.verification == .api }
    }

    var body: some View {
        Form {
            Section {
                Text("Your provider's own caps are what actually stop a runaway bill. Kill Cord can't turn them on "
                    + "for you: open each setting, set it, and mark it done. Caps can be removed later, so Kill Cord "
                    + "asks you to look again after 30 days.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if canCheck {
                    HStack {
                        Text("Some of these can be checked with your key.").font(.callout)
                        Spacer()
                        if checking { ProgressView().controlSize(.small) }
                        Button("Check Now") {
                            checking = true
                            Task {
                                await model.checkCaps(provider)
                                checking = false
                            }
                        }
                        .disabled(checking || model.isDemo)
                    }
                }
            } header: {
                Text("\(provider.info.name) caps")
            }
            ForEach(CapsCatalog.controls(for: provider)) { control in
                CapRow(control: control, model: model, isConnected: model.connected.contains(provider))
            }
        }
        .formStyle(.grouped)
    }
}

struct CapRow: View {
    let control: CapControl
    let model: SpendModel
    let isConnected: Bool

    var body: some View {
        let status = model.audit.status(of: control, now: Date())
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    badge(control.enforcement.label,
                          color: control.enforcement == .alertOnly ? .blue : (control.enforcement == .hardStop ? .green : .teal))
                    badge(control.verification == .api ? "Checked by API" : "Self-reported", color: .secondary)
                }
                Text(control.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(control.steps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)").font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let caveat = control.caveat {
                    Text(caveat).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                statusLine(status)
                HStack {
                    Button("Open This Setting") { NSWorkspace.shared.open(control.consoleURL) }
                        .buttonStyle(.borderedProminent)
                    Button("Docs") { NSWorkspace.shared.open(control.docURL) }
                    Spacer()
                    markButtons(status)
                }
                .controlSize(.small)
            }
        } header: {
            Text(control.name)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private func statusLine(_ status: CapAuditState.Status) -> some View {
        switch status {
        case .notDone:
            Label("Not done yet", systemImage: "circle").foregroundStyle(.orange)
        case .markedDone(let at, let recheck):
            if recheck {
                Label("You marked this done \(SpendText.time(at)). Worth checking it's still on.",
                      systemImage: "arrow.clockwise.circle").foregroundStyle(.orange)
            } else {
                Label("Done (you marked it \(SpendText.time(at)))", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        case .notApplicable:
            Label("Not needed", systemImage: "minus.circle").foregroundStyle(.secondary)
        case .verifiedOn(let detail, _):
            Label(detail, systemImage: "checkmark.seal").foregroundStyle(.green)
        case .verifiedOff(let detail, _):
            Label(detail, systemImage: "xmark.seal").foregroundStyle(.orange)
        case .enforced(let detail, _):
            Label(detail, systemImage: "stop.circle").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func markButtons(_ status: CapAuditState.Status) -> some View {
        switch status {
        case .notDone, .verifiedOff:
            Button("Not Needed") { model.mark(control.id, .notApplicable(at: Date())) }
            Button("Mark Done") { model.mark(control.id, .done(at: Date())) }
        case .markedDone(_, let recheck):
            if recheck {
                Button("Still On") { model.mark(control.id, .done(at: Date())) }
            }
            Button("Undo") { model.mark(control.id, nil) }
        case .notApplicable:
            Button("Undo") { model.mark(control.id, nil) }
        case .verifiedOn, .enforced:
            EmptyView()
        }
    }
}
