import AppKit
import KillCordCore
import PanelKit
import SwiftUI

/// The guided native-caps audit: for each provider, a checklist of the spend controls it offers, whether
/// each stops spend or only alerts, a link to the exact console page, and how to mark it. Kill Cord never
/// changes a cap itself.
struct CapsAuditView: View {
    let model: SpendModel
    @State private var selection: ProviderID

    init(model: SpendModel, selection: ProviderID? = nil) {
        self.model = model
        // Open on the first provider with something to look at.
        let first = model.auditProviders.first { model.audit.progress(for: $0, now: Date()).needsAttention > 0 }
        _selection = State(initialValue: selection ?? first ?? .anthropic)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarPicker(groups: [.init(title: "Providers", items: Self.providers)],
                          selection: $selection) { provider in
                CapsProviderRow(provider: provider, light: Self.light(model.audit.progress(for: provider, now: Date())),
                                line: line(provider))
            }
            .frame(width: 230)
            Divider()
            ProviderCapsView(provider: selection, model: model)
                .id(selection)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 600)
    }

    /// Providers with at least one native cap Kill Cord knows about.
    static var providers: [ProviderID] { ProviderID.allCases.filter { !CapsCatalog.controls(for: $0).isEmpty } }

    static func light(_ progress: CapAuditState.Progress) -> SignalLight {
        if progress.isComplete { return .go }
        if progress.done == 0 { return .off }
        return .caution
    }

    private func line(_ provider: ProviderID) -> String {
        let progress = model.audit.progress(for: provider, now: Date())
        if progress.isComplete { return "All \(progress.total) done" }
        let attention = progress.needsAttention
        return "\(progress.done) of \(progress.total) done" + (attention > 0 && progress.done > 0
            ? ", \(attention) to check" : "")
    }
}

struct CapsProviderRow: View {
    let provider: ProviderID
    let light: SignalLight
    let line: String

    var body: some View {
        HStack(spacing: 9) {
            ProviderMark(provider: provider)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.info.name).lineLimit(1)
                HStack(spacing: 5) {
                    StatusLED(light.panel, size: 6)
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.info.name), \(line)")
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
        let progress = model.audit.progress(for: provider, now: Date())
        VStack(spacing: 0) {
            ProviderHeader(
                provider: provider, title: "\(provider.info.name) caps",
                status: CapsAuditView.light(progress).panel,
                statusLabel: progress.isComplete ? "All done" : "\(progress.done) of \(progress.total) done",
                chips: [],
                message: "Your provider's own caps are what stop a runaway bill. Turn each one on in the "
                    + "provider's console, then mark it here. Kill Cord asks you to look again after 30 days."
            )
            Form {
                if canCheck {
                    Section {
                        LabeledContent {
                            HStack(spacing: 8) {
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
                        } label: {
                            Text("Check with your key")
                            Text("\(provider.info.name)'s API can confirm some of these. Kill Cord also checks "
                                + "every 6 hours.")
                        }
                    }
                }
                ForEach(CapsCatalog.controls(for: provider)) { control in
                    CapRow(control: control, model: model)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct CapRow: View {
    let control: CapControl
    let model: SpendModel
    @State private var showsSteps: Bool?

    var body: some View {
        let status = model.audit.status(of: control, now: Date())
        let expanded = showsSteps ?? status.needsAttention
        Section {
            Text(control.summary).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(isExpanded: Binding(get: { expanded }, set: { showsSteps = $0 })) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(control.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                            Text(step).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let caveat = control.caveat {
                        Label(caveat, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.callout)
                .padding(.top, 4)
            } label: {
                Text("How to turn it on").font(.callout)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusLED(status.light.panel)
                Text(statusSentence(status)).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                if status.isDone {
                    Button("Open Setting") { NSWorkspace.shared.open(control.consoleURL) }
                } else {
                    Button("Open Setting") { NSWorkspace.shared.open(control.consoleURL) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Read Docs") { NSWorkspace.shared.open(control.docURL) }
                Spacer()
                markButtons(status)
            }
        } header: {
            // One line when it fits; otherwise the chips move under the name instead of squeezing it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    title(status).fixedSize()
                    Spacer()
                    chips
                }
                VStack(alignment: .leading, spacing: 5) {
                    title(status)
                    chips.padding(.leading, 16)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func title(_ status: CapAuditState.Status) -> some View {
        HStack(spacing: 8) {
            StatusLED(status.light.panel)
            Text(control.name).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            Chip(text: control.enforcement.label, tint: enforcementTint)
            Chip(text: control.verification == .api ? "Kill Cord can check" : "You mark it")
        }
    }

    private var enforcementTint: Color {
        switch control.enforcement {
        case .hardStop: .green
        case .partialStop: .teal
        case .alertOnly: .secondary
        }
    }

    private func statusSentence(_ status: CapAuditState.Status) -> String {
        switch status {
        case .notDone: "Not done yet."
        case .markedDone(let at, let recheck):
            recheck ? "You marked this done \(SpendText.time(at)). Check it's still on."
                : "Done. You marked it \(SpendText.time(at))."
        case .notApplicable: "Marked not needed."
        case .verifiedOn(let detail, _), .verifiedOff(let detail, _), .enforced(let detail, _): detail
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
