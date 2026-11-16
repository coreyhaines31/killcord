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
    @AppStorage(Preferences.menuBarPeriodKey) private var menuBarPeriod = SpendText.MenuBarPeriod.today
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
                Toggle("Launch at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Picker("Menu bar shows", selection: $menuBarPeriod) {
                    ForEach(SpendText.MenuBarPeriod.allCases) { Text("Total spend \($0.title.lowercased())").tag($0) }
                }
                Picker("Check spend every", selection: $interval) {
                    ForEach(RefreshScheduler.intervalChoices, id: \.self) { Text(SpendText.duration($0)).tag($0) }
                }
                .onChange(of: interval) { _, value in model.setRefreshInterval(value) }
            } footer: {
                Text("Kill Cord checks only while your Mac is awake and Kill Cord is running. After sleep it says "
                    + "when it last checked instead of showing old numbers as live. Some providers are only asked "
                    + "hourly, since their data runs hours behind. Always-on monitoring (coming later).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check for updates automatically", isOn: $checksForUpdates)
                    .onChange(of: checksForUpdates) { _, enabled in updater.checksAutomatically = enabled }
                    .disabled(!Updater.isConfigured)
                LabeledContent("Version \(Self.version)") {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!Updater.isConfigured)
                }
            } footer: {
                Text("Kill Cord goes online only to ask your providers' billing APIs and to check for updates. "
                    + "No telemetry, no account. Your keys never leave your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            uninstallSection
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }

    private var uninstallSection: some View {
        Section {
            LabeledContent("Keys and local data") {
                Button("Remove All…", role: .destructive) { confirmingRemoval = true }
            }
            if let removalError {
                Label(removalError, systemImage: "exclamationmark.circle").font(.callout)
            }
        } header: {
            Text("Uninstall")
        } footer: {
            Text("Removes every provider key from the Keychain, the saved spend in ~/Library/Application Support/"
                + "\(Brand.name), and these settings. Then drag \(Brand.name) to the Trash. Keys can also be "
                + "removed in Keychain Access (search \"\(Brand.keychainService)\").")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Remove all keys and local data?", isPresented: $confirmingRemoval) {
            Button("Remove All", role: .destructive) {
                do {
                    try model.removeEverything()
                    removalError = nil
                } catch {
                    removalError = "Couldn't remove every key: \(error.localizedDescription)"
                }
            }
        } message: {
            Text("Kill Cord forgets every provider. This doesn't revoke the keys with the providers; do that in "
                + "their consoles if you no longer need them.")
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
