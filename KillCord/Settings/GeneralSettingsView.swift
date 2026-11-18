import AppKit
import KillCordCore
import os
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    private static let logger = Logger(subsystem: Brand.bundleIdentifier, category: "Settings")

    let updater: Updater
    let model: SpendModel
    @State private var checksForUpdates: Bool
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var interval: TimeInterval = Preferences.refreshInterval
    @AppStorage(Preferences.menuBarPeriodKey, store: Preferences.defaults)
    private var menuBarPeriod = SpendText.MenuBarPeriod.today
    @State private var confirmingRemoval = false
    @State private var removalError: String?

    init(updater: Updater, model: SpendModel) {
        self.updater = updater
        self.model = model
        _checksForUpdates = State(initialValue: updater.checksAutomatically)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $launchesAtLogin) {
                    Text("Launch at login")
                    Text("Kill Cord can only check spend while it's running.")
                }
                .onChange(of: launchesAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Picker(selection: $menuBarPeriod) {
                    ForEach(SpendText.MenuBarPeriod.allCases) { Text("Total spend \($0.title.lowercased())").tag($0) }
                } label: {
                    Text("Menu bar shows")
                    Text("An asterisk means a number isn't live.")
                }
            }
            Section {
                Picker(selection: $interval) {
                    ForEach(RefreshScheduler.intervalChoices, id: \.self) { Text(SpendText.duration($0)).tag($0) }
                } label: {
                    Text("Check spend every")
                    Text("Slow providers are asked at most hourly, since their data runs hours behind.")
                }
                .onChange(of: interval) { _, value in model.setRefreshInterval(value) }
            } header: {
                Text("Checking")
            } footer: {
                Label("Kill Cord checks only while your Mac is awake and Kill Cord is running. After sleep it shows "
                    + "when it last checked instead of passing old numbers off as live. Always-on monitoring "
                    + "(coming later).", systemImage: "moon.zzz")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle(isOn: $checksForUpdates) {
                    Text("Check for updates automatically")
                    Text("Kill Cord asks GitHub once a day for a newer version.")
                }
                .onChange(of: checksForUpdates) { _, enabled in updater.checksAutomatically = enabled }
                .disabled(!Updater.isConfigured)
                LabeledContent("Version \(Self.version)") {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!Updater.isConfigured)
                }
            } header: {
                Text("Updates")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Kill Cord goes online only to read your providers' billing APIs and to check for updates. "
                        + "No telemetry, no account.", systemImage: "lock.fill")
                    Text("Logos are trademarks of their owners and are used only to identify the services "
                        + "Kill Cord reads.")
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            uninstallSection
        }
        .formStyle(.grouped)
        .frame(height: 560)
    }

    private var uninstallSection: some View {
        Section {
            LabeledContent {
                Button("Remove All…", role: .destructive) { confirmingRemoval = true }
            } label: {
                Text("Remove keys and local data")
                Text("Deletes every key from your Keychain, the saved spend, and these settings.")
            }
            if let removalError {
                ResultBox(light: .stop, title: "Couldn't remove every key", message: removalError,
                          fix: "Delete the rest in Keychain Access: search \"\(Brand.keychainService)\".")
            }
        } header: {
            Text("Uninstall")
        } footer: {
            Text("Then drag \(Brand.name) to the Trash. Saved spend lives in ~/Library/Application Support/"
                + "\(Brand.name). Keys are also in Keychain Access under \"\(Brand.keychainService)\".")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Remove all keys and local data?", isPresented: $confirmingRemoval) {
            Button("Remove All", role: .destructive) {
                do {
                    try model.removeEverything()
                    removalError = nil
                } catch {
                    removalError = error.localizedDescription
                }
            }
        } message: {
            Text("Kill Cord forgets every provider. The keys keep working with each provider until you revoke "
                + "them in its console.")
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Couldn't change launch at login: \(error.localizedDescription)")
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
