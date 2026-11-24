import AppKit
import KillCordCore
import SwiftUI

/// Starting a manual entry from a service Kill Cord knows has no billing API. Picking one fills in the name.
struct ManualPresetSection: View {
    @Binding var serviceName: String?

    private var preset: ManualPreset? { ManualPreset.matching(serviceName) }

    var body: some View {
        Section {
            LabeledContent {
                Menu(preset?.name ?? "Choose a Service") {
                    ForEach(ManualPreset.all) { item in
                        Button(item.name) { serviceName = item.name }
                    }
                }
                .fixedSize()
            } label: {
                Text("Service")
                Text("Services Kill Cord knows have no billing API. Or type any name below.")
            }
            if let preset { ManualPresetNote(preset: preset) }
        } header: {
            Text("No billing API: enter it by hand")
        }
    }
}

/// Says plainly that the service has no billing API, with its billing page and docs.
struct ManualPresetNote: View {
    let preset: ManualPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(preset.name) has no billing API, so Kill Cord can't read it. \(preset.note) Copy your plan "
                + "from its billing page.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(preset.billingURL)
                } label: {
                    Label("Open \(preset.name) Billing", systemImage: "arrow.up.forward.app")
                }
                .help(preset.billingURL.absoluteString)
                Button("Read \(preset.name)'s Billing Docs") { NSWorkspace.shared.open(preset.docURL) }
                    .buttonStyle(.link)
                    .help(preset.docURL.absoluteString)
            }
        }
    }
}
