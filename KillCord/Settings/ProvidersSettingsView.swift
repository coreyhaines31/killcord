import AppKit
import KillCordCore
import SwiftUI

/// Connect, replace, or remove each provider's key. Keys go straight to the Keychain after the provider
/// accepts them, and are never shown again.
struct ProvidersSettingsView: View {
    let model: SpendModel
    @State private var selection: ProviderID = .anthropic

    var body: some View {
        HStack(spacing: 0) {
            List(ProviderID.allCases, selection: $selection) { provider in
                HStack {
                    Text(provider.info.name)
                    Spacer()
                    statusDot(provider)
                }
                .tag(provider)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            Divider()
            ProviderEditor(provider: selection, model: model)
                .id(selection)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 560)
    }

    private func statusDot(_ provider: ProviderID) -> some View {
        let color: Color = if !provider.info.connects {
            .clear
        } else if !model.connected.contains(provider) {
            .secondary.opacity(0.3)
        } else if model.states[provider]?.lastError?.isTransient == false {
            .orange
        } else {
            .green
        }
        return Circle().fill(color).frame(width: 7, height: 7)
    }
}

struct ProviderEditor: View {
    let provider: ProviderID
    let model: SpendModel
    @State private var values: [String: String] = [:]
    @State private var isChecking = false
    @State private var error: String?
    @State private var saved = false
    @State private var confirmingRemoval = false

    private var info: ProviderInfo { provider.info }
    private var isConnected: Bool { model.connected.contains(provider) }

    var body: some View {
        Form {
            Section {
                Text(info.capability.summary).font(.callout)
                if !info.connects {
                    Text(info.lag.note).font(.callout).foregroundStyle(.secondary)
                    Link("Open Supabase Billing", destination: info.consoleURL)
                }
            } header: {
                Text(info.name)
            }
            if info.connects {
                if provider == .google { googleSetup }
                fieldsSection
                if let warning = info.keyPowerWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text("What this key can do")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private var fieldsSection: some View {
        Section {
            ForEach(info.fields) { field in
                fieldRow(field)
            }
            HStack {
                if isConnected {
                    Button("Remove Key…", role: .destructive) { confirmingRemoval = true }
                }
                Spacer()
                if isChecking { ProgressView().controlSize(.small) }
                Button(isConnected ? "Replace" : "Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isChecking)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else if saved {
                Label("Connected. Saved in your Keychain.", systemImage: "checkmark.circle")
                    .font(.callout)
            }
        } header: {
            Text(isConnected ? "Connected" : "Connect")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your key stays on this Mac, in the macOS Keychain. Kill Cord sends it only to \(info.name), "
                    + "to read billing, and never writes it to a file or log.")
                if let url = info.keyURL {
                    Link("Create a \(info.keyKind.lowercased())", destination: url)
                }
                Text("Never paste a key into a chat or an AI agent to set this up. If you have, revoke it and make "
                    + "a new one.")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Remove the \(info.name) key?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) {
                do {
                    try model.disconnect(provider)
                    values = [:]
                    saved = false
                    error = nil
                } catch {
                    self.error = "The Keychain wouldn't remove the key. Try again, or delete it in Keychain Access."
                }
            }
        } message: {
            Text("Kill Cord deletes it from the Keychain and stops checking \(info.name). The key still works "
                + "with \(info.name) until you revoke it there.")
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: CredentialField) -> some View {
        let binding = Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = $0 })
        let placeholder = field.isSecret && isConnected ? "Saved in Keychain. Paste to replace." : field.placeholder
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label + (field.isOptional ? " (optional)" : "")).font(.callout)
            if field.isMultiline {
                // A JSON key file. Not echoed back once saved.
                TextEditor(text: binding)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 70)
                    .overlay(alignment: .topLeading) {
                        if binding.wrappedValue.isEmpty {
                            Text(placeholder).font(.system(size: 11)).foregroundStyle(.tertiary).padding(4)
                                .allowsHitTesting(false)
                        }
                    }
            } else if field.isSecret {
                SecureField("", text: binding, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("", text: binding, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
            }
            if !field.help.isEmpty {
                Text(field.help).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var googleSetup: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Google has no API for current spend, and the Gemini API has none either. Kill Cord reads your "
                    + "Cloud Billing export in BigQuery instead:")
                Text("1. Turn on the standard usage cost export to a BigQuery dataset (Billing › Billing export).")
                Text("2. Create a service account with BigQuery Data Viewer on that dataset and BigQuery Job User "
                    + "on its project. Add Billing Account Viewer to let Kill Cord check budgets and spend caps.")
                Text("3. Create a JSON key for it and paste it below, with the export table's full name.")
                Text("The export runs hours behind, typically up to a day. Data appears a few hours after you "
                    + "turn it on.").foregroundStyle(.secondary)
                Link("Open Billing export", destination: URL(string: "https://console.cloud.google.com/billing/export")!)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("One-time setup")
        }
    }

    private func load() {
        // Non-secret fields are shown for editing; secrets never are.
        guard let stored = model.storedCredentials(provider) else { return }
        for field in info.fields where !field.isSecret {
            values[field.id] = stored[field.id] ?? ""
        }
    }

    private func connect() {
        error = nil
        saved = false
        let entered = values
        let missing = ProviderCredentials(provider: provider, values: entered).missingFields
            .filter { !($0.isSecret && isConnected) }
        if let first = missing.first {
            error = "Fill in \(first.label)."
            return
        }
        isChecking = true
        Task {
            do {
                try await model.connect(provider, values: entered)
                saved = true
                // Clear secrets from memory and the screen once they're in the Keychain.
                for field in info.fields where field.isSecret { values[field.id] = "" }
            } catch let spendError as SpendError {
                error = spendError.message(for: provider)
            } catch {
                self.error = error.localizedDescription
            }
            isChecking = false
        }
    }
}
