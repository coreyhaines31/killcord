import AppKit
import KillCordCore
import SwiftUI

/// Kill Cord Teams (preview): sign this Mac in, pick a workspace, see your own spend. Only shown when the
/// `teamsEnabled` flag is on.
struct TeamsSettingsView: View {
    let model: TeamsModel

    var body: some View {
        Form {
            switch model.state {
            case .signedOut, .startingSignIn:
                signedOut
            case .showingCode(let signIn):
                code(signIn)
            case .signedIn(let account):
                signedIn(account)
            case .failed(let error):
                Section {
                    Text(error.errorDescription ?? "Something went wrong.")
                        .foregroundStyle(.red)
                    Button("Try again") { model.signIn(deviceName: Self.deviceName) }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    static var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }

    private var signedOut: some View {
        Section {
            Text("Sign in to see your own spend in your team's Kill Cord workspace.")
            Text("Your provider keys stay on this Mac. Nothing is shared until you choose to.")
                .foregroundStyle(.secondary)
            Button(model.state == .startingSignIn ? "Starting…" : "Sign in") {
                model.signIn(deviceName: Self.deviceName)
            }
            .disabled(model.state == .startingSignIn)
        }
    }

    private func code(_ signIn: DeviceSignIn) -> some View {
        Section {
            Text("Approve this Mac in your browser. Check the code matches:")
            Text(signIn.userCode)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel("Sign-in code \(signIn.userCode)")
            HStack {
                Button("Open browser") { NSWorkspace.shared.open(signIn.verificationURIComplete) }
                Button("Cancel") { model.cancelSignIn() }
            }
            Text("Waiting for approval. The code expires in 10 minutes.")
                .foregroundStyle(.secondary)
        }
    }

    private func signedIn(_ account: TeamsMe) -> some View {
        Group {
            Section {
                LabeledContent("Signed in as", value: account.email)
                Picker("Workspace", selection: Binding(
                    get: { model.selectedWorkspaceID ?? "" },
                    set: { model.select($0) }
                )) {
                    ForEach(account.workspaces) { Text($0.name).tag($0.id) }
                }
            }
            Section("My spend this month") {
                if let error = model.spendError {
                    Text(error).foregroundStyle(.red)
                }
                if let spend = model.spend {
                    LabeledContent("Total", value: MoneyText.string(Money(spend.total)))
                    ForEach(Array(spend.units.enumerated()), id: \.offset) { _, unit in
                        LabeledContent(unit.label + (unit.how == .reported ? " (reported)" : " (assigned)"),
                                       value: MoneyText.string(Money(unit.amount)))
                    }
                    if spend.units.isEmpty {
                        Text("Nothing is attributed to you yet.").foregroundStyle(.secondary)
                    }
                } else if model.spendError == nil {
                    Text("Loading…").foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Sign out") { model.signOut() }
            }
        }
    }
}
