import AppKit
import KillCordCore
import PanelKit
import SwiftUI

/// Connect, check, replace or remove each provider's key. The sidebar is a status board; the detail walks
/// through setup, then shows what Kill Cord read. Keys go to the Keychain only after the provider accepts
/// them, and are never shown again.
struct ProvidersSettingsView: View {
    let model: SpendModel
    var openTab: @MainActor (SettingsWindow.Tab) -> Void = { _ in }
    @State private var selection: ProviderID?
    private let editorStart: ProviderEditor.Start

    init(model: SpendModel, selection: ProviderID = .anthropic, editorStart: ProviderEditor.Start = .init(),
         openTab: @escaping @MainActor (SettingsWindow.Tab) -> Void = { _ in }) {
        self.model = model
        self.openTab = openTab
        self.editorStart = editorStart
        _selection = State(initialValue: selection)
    }

    private var connected: [ProviderID] { ProviderID.allCases.filter { model.connected.contains($0) } }
    private var available: [ProviderID] { ProviderID.allCases.filter { !model.connected.contains($0) } }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                if !connected.isEmpty {
                    Section("Connected") {
                        ForEach(connected) { ProviderRow(provider: $0, status: model.status($0)).tag(Optional($0)) }
                    }
                }
                Section(connected.isEmpty ? "Providers" : "Not connected") {
                    ForEach(available) { ProviderRow(provider: $0, status: model.status($0)).tag(Optional($0)) }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 230)
            Divider()
            ProviderEditor(provider: selection ?? .anthropic, model: model, start: editorStart, openTab: openTab)
                .id(selection)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 600)
    }
}

/// One sidebar row: monogram, name, and a status line with its light.
struct ProviderRow: View {
    let provider: ProviderID
    let status: ProviderStatus

    var body: some View {
        HStack(spacing: 9) {
            ProviderMark(provider: provider)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.info.name).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 5) {
                    StatusLED(status.light.panel, size: 6)
                    Text(status.line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .help("\(provider.info.name): \(status.line)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.info.name), \(status.line)")
    }
}

/// The detail for one provider, in whichever state it's in: setup, checking, failed, connected, or caps only.
struct ProviderEditor: View {
    /// Where the editor starts. Settings always starts empty; the render harness starts mid-flow.
    struct Start {
        var values: [String: String] = [:]
        var phase: Phase = .idle
        var showsWhy = false
    }

    enum Phase: Equatable {
        case idle
        case checking
        case failed(title: String, message: String?, fix: String?)
        /// The provider accepted the key just now.
        case connected
    }

    let provider: ProviderID
    let model: SpendModel
    let openTab: @MainActor (SettingsWindow.Tab) -> Void
    @State private var values: [String: String]
    @State private var phase: Phase
    @State private var showsWhy: Bool
    @State private var replacing = false
    @State private var confirmingRemoval = false
    @State private var removalError: String?
    @State private var hints: [(field: CredentialField, text: String)] = []
    @Environment(\.panelTheme) private var theme

    init(provider: ProviderID, model: SpendModel, start: Start = .init(),
         openTab: @escaping @MainActor (SettingsWindow.Tab) -> Void) {
        self.provider = provider
        self.model = model
        self.openTab = openTab
        _values = State(initialValue: start.values)
        _phase = State(initialValue: start.phase)
        _showsWhy = State(initialValue: start.showsWhy)
    }

    private var info: ProviderInfo { provider.info }
    private var isConnected: Bool { model.connected.contains(provider) }
    private var status: ProviderStatus { model.status(provider, isChecking: phase == .checking) }

    var body: some View {
        VStack(spacing: 0) {
            ProviderHeader(provider: provider, title: info.name, status: status.light.panel,
                           statusLabel: status.label, chips: [info.capabilityLabel], message: info.overview)
            Form {
                if !info.connects {
                    CapsSummarySection(provider: provider, model: model, openTab: openTab)
                    Section {
                        LabeledContent {
                            Button {
                                NSWorkspace.shared.open(info.consoleURL)
                            } label: {
                                Label("Open \(info.name) Billing", systemImage: "arrow.up.forward.app")
                            }
                        } label: {
                            Text("Your spend")
                            Text("See the Upcoming Invoice on \(info.name)'s Billing page.")
                        }
                    }
                } else if isConnected && !replacing {
                    connectedSections
                } else {
                    setupSection
                }
            }
            .formStyle(.grouped)
        }
        .onAppear(perform: load)
    }

    // MARK: - Setup

    private var setupSection: some View {
        let steps = info.setupSteps
        return Section {
            if !replacing {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    SetupStepRow(number: index + 1, title: step.title, detail: step.detail) {
                        if let link = step.link {
                            Button {
                                NSWorkspace.shared.open(link.url)
                            } label: {
                                Label(link.title, systemImage: "arrow.up.forward.app")
                            }
                            .help(link.url.absoluteString)
                        }
                        if index == steps.count - 1 { keyPowerNote }
                    }
                }
            }
            SetupStepRow(number: replacing ? 1 : steps.count + 1, title: pasteTitle, detail: nil) {
                CredentialFields(fields: info.fields, values: $values, keepsSavedSecrets: replacing,
                                 isDisabled: phase == .checking)
                connectRow
                outcome
            }
        } header: {
            Text(replacing ? "Replace the key" : "Connect in \(steps.count + 1) steps")
        } footer: {
            PrivacyLine(providerName: info.name)
        }
    }

    private var pasteTitle: String {
        if replacing { return "Paste the new key. Leave a secret empty to keep the saved one." }
        if info.fields.count == 1, let field = info.fields.first {
            return "Paste the \(field.label.prefix(1).lowercased() + field.label.dropFirst()) here"
        }
        return "Fill in these fields"
    }

    @ViewBuilder
    private var keyPowerNote: some View {
        if let summary = info.keyPowerSummary {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.caution)
                        .accessibilityLabel("Warning")
                    Text(summary).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(showsWhy ? "Hide" : "Why?") { withAnimation(.snappy) { showsWhy.toggle() } }
                        .buttonStyle(.link)
                        .font(.callout)
                        .accessibilityHint("Shows what this key can do")
                }
                if showsWhy, let warning = info.keyPowerWarning {
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 20)
                }
            }
            .padding(.top, 2)
        }
    }

    private var connectRow: some View {
        HStack(spacing: 8) {
            if phase == .checking {
                ProgressView().controlSize(.small)
                Text("Checking with \(info.name)…").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if replacing {
                Button("Cancel") {
                    replacing = false
                    phase = .idle
                    load()
                }
                .keyboardShortcut(.cancelAction)
            }
            Button(replacing ? "Save New Key" : "Connect \(info.name)", action: connect)
                .keyboardShortcut(.defaultAction)
                .disabled(phase == .checking)
        }
    }

    @ViewBuilder
    private var outcome: some View {
        if case .failed(let title, let message, let fix) = phase {
            ResultBox(light: .stop, title: title, message: message, fix: fix)
        } else if phase == .idle, !replacing {
            Text("Kill Cord checks the key with \(info.name) before saving it. Today's spend shows up here next.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func load() {
        hints = model.keyHints(provider)
        guard let stored = model.storedCredentials(provider) else { return }
        // Non-secret fields come back for editing; secrets never do.
        for field in info.fields where !field.isSecret && values[field.id] == nil {
            values[field.id] = stored[field.id] ?? ""
        }
    }

    private func connect() {
        let entered = values
        let missing = ProviderCredentials(provider: provider, values: entered).missingFields
            .filter { !($0.isSecret && replacing) }
        if let first = missing.first {
            phase = .failed(title: "Fill in \(first.label)", message: nil, fix: nil)
            return
        }
        phase = .checking
        Task {
            do {
                try await model.connect(provider, values: entered)
                // Clear secrets from memory and the screen once they're in the Keychain.
                for field in info.fields where field.isSecret { values[field.id] = "" }
                replacing = false
                hints = model.keyHints(provider)
                phase = .connected
            } catch let error as SpendError {
                phase = .failed(title: error.shortLabel, message: error.message(for: provider),
                                fix: error.fix(for: provider))
            } catch {
                phase = .failed(title: "Couldn't save the key", message: error.localizedDescription, fix: nil)
            }
        }
    }

    private func remove() {
        do {
            try model.disconnect(provider)
            values = [:]
            hints = []
            phase = .idle
            removalError = nil
        } catch {
            removalError = "Your Keychain wouldn't delete it. Try again, or delete it in Keychain Access."
        }
    }
}

extension ProviderEditor {
    // MARK: - Connected

    @ViewBuilder
    private var connectedSections: some View {
        Section("Spend") {
            if phase == .connected {
                ResultBox(light: .go, title: "Connected", message: "\(info.name) accepted the key. It's saved in "
                    + "your Keychain.", fix: nil)
            }
            let state = model.states[provider]
            // A key that was never accepted has nothing to read out; the problem says it all.
            if state?.snapshot != nil || state?.lastError?.isTransient != false {
                SpendReadout(provider: provider, model: model)
            }
            problem
            HStack(spacing: 8) {
                Button {
                    model.refresh(provider)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.inFlight.contains(provider) || model.isDemo)
                .help(model.isDemo ? "Sample data doesn't refresh" : "Check \(info.name) now")
                Spacer()
                Button {
                    NSWorkspace.shared.open(info.consoleURL)
                } label: {
                    Label("Compare in \(info.consoleName)", systemImage: "arrow.up.forward.app")
                }
            }
        }
        Section {
            ForEach(hints, id: \.field.id) { hint in
                LabeledContent(hint.field.label) {
                    Text(hint.text).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Replace Key…") {
                    replacing = true
                    phase = .idle
                }
                Button("Remove Key…", role: .destructive) { confirmingRemoval = true }
            }
            if let removalError {
                ResultBox(light: .stop, title: "Couldn't remove the key", message: removalError, fix: nil)
            }
        } header: {
            Text("Key")
        } footer: {
            PrivacyLine(providerName: info.name)
        }
        .confirmationDialog("Remove the \(info.name) key?", isPresented: $confirmingRemoval) {
            Button("Remove Key", role: .destructive, action: remove)
        } message: {
            Text("Kill Cord deletes it from your Keychain and stops checking \(info.name). The key keeps working "
                + "until you revoke it in the \(info.consoleName).")
        }
        CapsSummarySection(provider: provider, model: model, openTab: openTab)
    }

    @ViewBuilder
    private var problem: some View {
        if let error = model.states[provider]?.lastError {
            ResultBox(light: error.isTransient ? .caution : .stop, title: error.shortLabel,
                      message: error.message(for: provider), fix: error.isTransient ? nil : error.fix(for: provider)) {
                if !error.isTransient {
                    Button("Replace Key…") {
                        replacing = true
                        phase = .idle
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
