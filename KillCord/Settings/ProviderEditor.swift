import AppKit
import KillCordCore
import PanelKit
import SwiftUI

/// The detail for one connection, or a provider being connected, in whichever state it's in: setup,
/// checking, failed, connected, or caps only.
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
    /// Nil while connecting a new account.
    let connectionID: UUID?
    let model: SpendModel
    /// Moves the sidebar, after a connect (`true`) or a removal.
    let select: (ProviderSidebarItem, Bool) -> Void
    let openTab: @MainActor (SettingsTab) -> Void
    @State private var values: [String: String]
    @State private var name = ""
    @State private var phase: Phase
    @State private var showsWhy: Bool
    @State private var replacing = false
    @State private var confirmingRemoval = false
    @State private var removalError: String?
    @State private var hints: [(field: CredentialField, text: String)] = []
    @Environment(\.panelTheme) private var theme

    init(provider: ProviderID, connectionID: UUID?, model: SpendModel, start: Start = .init(),
         justConnected: Bool = false, select: @escaping (ProviderSidebarItem, Bool) -> Void = { _, _ in },
         openTab: @escaping @MainActor (SettingsTab) -> Void) {
        self.provider = provider
        self.connectionID = connectionID
        self.model = model
        self.select = select
        self.openTab = openTab
        _values = State(initialValue: start.values)
        _phase = State(initialValue: justConnected ? .connected : start.phase)
        _showsWhy = State(initialValue: start.showsWhy)
    }

    private var info: ProviderInfo { provider.info }
    private var record: ConnectionRecord? { connectionID.flatMap(model.connection) }
    private var isConnected: Bool { record != nil }
    /// Connecting a second (or later) account of a provider that already has one.
    private var isAddingAnother: Bool { record == nil && !model.connections(for: provider).isEmpty }
    private var status: ProviderStatus {
        if let connectionID { return model.status(connectionID, isChecking: phase == .checking) }
        return model.status(provider, isChecking: phase == .checking)
    }

    private var title: String {
        if let record { return record.name }
        return isAddingAnother ? "New \(info.name) account" : info.name
    }

    private var chips: [String] {
        var chips = [info.capabilityLabel]
        if provider == .custom { chips.append("Not verified by Kill Cord") }
        if let record, record.name != info.name { chips.insert(info.name, at: 0) }
        return chips
    }

    var body: some View {
        VStack(spacing: 0) {
            ProviderHeader(provider: provider, title: title, status: status.light.panel,
                           statusLabel: status.label, chips: chips, message: info.overview)
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
            if replacing {
                Text("Replace the key")
            } else if isAddingAnother {
                Text("Add another \(info.name) account in \(steps.count + 1) steps")
            } else {
                Text(provider == .manual ? "Add in \(steps.count + 1) steps" : "Connect in \(steps.count + 1) steps")
            }
        } footer: {
            PrivacyLine(providerName: provider == .custom ? "the address you enter" : info.name,
                        isManual: provider == .manual)
        }
    }

    private var pasteTitle: String {
        if replacing { return "Paste the new key. Leave a secret empty to keep the saved one." }
        if info.fields.count == 1, let field = info.fields.first {
            // "Admin API key" reads "admin API key"; "API key" keeps its acronym.
            let label = field.label.dropFirst().first?.isLowercase == true
                ? field.label.prefix(1).lowercased() + field.label.dropFirst() : field.label
            return "Paste the \(label) here"
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
            } else if isAddingAnother, let first = model.connections(for: provider).first {
                Button("Cancel") { select(.connection(first.id), false) }
                    .keyboardShortcut(.cancelAction)
            }
            Button(connectTitle, action: connect)
                .keyboardShortcut(.defaultAction)
                .disabled(phase == .checking)
        }
    }

    @ViewBuilder
    private var outcome: some View {
        if case .failed(let title, let message, let fix) = phase {
            ResultBox(light: .stop, title: title, message: message, fix: fix)
        } else if phase == .idle, !replacing, provider == .manual {
            Text("Kill Cord never contacts the service. It shows what you entered as not live, and reminds you "
                + "before the renewal.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if phase == .idle, !replacing, provider == .custom {
            Text("Kill Cord calls the address once to test it before saving. It can't verify the numbers it reads.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if phase == .idle, !replacing {
            Text(isAddingAnother
                ? "Use a key from the other \(info.name) account. Kill Cord checks it with \(info.name) before saving it."
                : "Kill Cord checks the key with \(info.name) before saving it. Today's spend shows up here next.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Actions

    private func load() {
        name = record?.name ?? ""
        hints = connectionID.map(model.keyHints) ?? []
        guard let connectionID, let stored = model.storedCredentials(connectionID) else { return }
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
                let id = try await model.connect(provider, replacing: replacing ? connectionID : nil, values: entered)
                // Clear secrets from memory and the screen once they're in the Keychain.
                for field in info.fields where field.isSecret { values[field.id] = "" }
                guard id == connectionID else {
                    select(.connection(id), true)
                    return
                }
                replacing = false
                hints = model.keyHints(id)
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
        guard let connectionID else { return }
        do {
            try model.disconnect(connectionID)
            removalError = nil
            let next = model.connections(for: provider).first.map { ProviderSidebarItem.connection($0.id) }
            select(next ?? .new(provider), false)
        } catch {
            removalError = "Your Keychain wouldn't delete it. Try again, or delete it in Keychain Access."
        }
    }
}

extension ProviderEditor {
    // MARK: - Connected

    @ViewBuilder
    private var connectedSections: some View {
        Section(sectionTitle) {
            if phase == .connected {
                ResultBox(light: .go, title: "Connected", message: "\(info.name) accepted the key. It's saved in "
                    + "your Keychain.", fix: nil)
            }
            let state = connectionID.flatMap { model.states[$0] }
            // A key that was never accepted has nothing to read out; the problem says it all.
            if let connectionID, state?.snapshot != nil || state?.lastError?.isTransient != false {
                SpendReadout(connectionID: connectionID, provider: provider, model: model)
            }
            problem
            if provider != .manual { // Nothing to check.
                HStack(spacing: 8) {
                    Button {
                        if let connectionID { model.refresh(connectionID) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(connectionID.map(model.inFlight.contains) ?? true || model.isDemo)
                    .help(model.isDemo ? "Sample data doesn't refresh" : "Check \(info.name) now")
                    Spacer()
                    if provider != .custom {
                        Button {
                            NSWorkspace.shared.open(info.consoleURL)
                        } label: {
                            Label("Compare in \(info.consoleName)", systemImage: "arrow.up.forward.app")
                        }
                    }
                }
            }
            if let config = connectionID.flatMap(model.customConfig) {
                Text(customNote(config)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Section {
            LabeledContent("Name") {
                TextField("Name", text: $name, prompt: Text(info.name))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .onSubmit(commitName)
                    .onDisappear(perform: commitName)
                    .accessibilityLabel("Name for this \(info.name) account")
            }
            ForEach(hints, id: \.field.id) { hint in
                LabeledContent(hint.field.label) {
                    Text(hint.text).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                Button(provider == .manual ? "Edit Plan…" : "Replace Key…") {
                    replacing = true
                    phase = .idle
                }
                Button(provider == .manual ? "Remove…" : "Remove Key…", role: .destructive) { confirmingRemoval = true }
            }
            if let removalError {
                ResultBox(light: .stop, title: "Couldn't remove the key", message: removalError, fix: nil)
            }
            HStack {
                Spacer()
                Button(anotherTitle) { select(.new(provider), false) }
                    .help("Track another one with its own settings")
            }
        } header: {
            Text("Account")
        } footer: {
            PrivacyLine(providerName: provider == .custom ? "the address you enter" : info.name,
                        isManual: provider == .manual)
        }
        .confirmationDialog(provider == .manual ? "Remove \(title)?" : "Remove the \(title) key?",
                            isPresented: $confirmingRemoval) {
            Button(provider == .manual ? "Remove" : "Remove Key", role: .destructive, action: remove)
        } message: {
            Text(provider == .manual ? "Kill Cord deletes what you entered and stops reminding you."
                : "Kill Cord deletes it from your Keychain and stops checking \(title). The key keeps working "
                    + "until you revoke it in the \(info.consoleName).")
        }
        CapsSummarySection(provider: provider, model: model, openTab: openTab)
    }

    private var connectTitle: String {
        if provider == .manual { return replacing ? "Save Changes" : "Save" }
        if replacing { return "Save New Key" }
        return provider == .custom ? "Test and Save" : "Connect \(info.name)"
    }

    private func commitName() {
        guard let connectionID, name != record?.name else { return }
        model.rename(connectionID, to: name)
        name = record?.name ?? name
    }

    @ViewBuilder
    private var problem: some View {
        if let error = connectionID.flatMap({ model.states[$0] })?.lastError {
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
