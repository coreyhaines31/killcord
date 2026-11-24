import KillCordCore
import PanelKit
import SwiftUI

/// What the Providers sidebar can select: a saved connection, or a provider to connect (its first account,
/// or another one).
enum ProviderSidebarItem: Hashable {
    case connection(UUID)
    case new(ProviderID)
}

/// Connect, check, rename, replace or remove each connection's key. A provider can have several (two
/// Anthropic organizations). The sidebar is a status board grouped by provider; the detail walks through
/// setup, then shows what Kill Cord read. Keys go to the Keychain only after the provider accepts them, and
/// are never shown again.
struct ProvidersSettingsView: View {
    let model: SpendModel
    var openTab: @MainActor (SettingsTab) -> Void = { _ in }
    @State private var selection: ProviderSidebarItem
    @State private var justConnected: UUID?
    private let editorStart: ProviderEditor.Start

    init(model: SpendModel, selection: ProviderSidebarItem? = nil, editorStart: ProviderEditor.Start = .init(),
         openTab: @escaping @MainActor (SettingsTab) -> Void = { _ in }) {
        self.model = model
        self.openTab = openTab
        self.editorStart = editorStart
        let first = model.connections.first.map { ProviderSidebarItem.connection($0.id) } ?? .new(.anthropic)
        _selection = State(initialValue: selection ?? first)
    }

    var body: some View {
        HStack(spacing: 0) {
            ProvidersSidebar(model: model, selection: $selection)
                .frame(width: 230)
            Divider()
            editor
                .id(selection)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 600)
    }

    @ViewBuilder
    private var editor: some View {
        switch selection {
        case .connection(let id):
            if let record = model.connection(id) {
                ProviderEditor(provider: record.provider, connectionID: id, model: model, start: editorStart,
                               justConnected: justConnected == id, select: select, openTab: openTab)
            } else {
                ProviderEditor(provider: .anthropic, connectionID: nil, model: model, select: select, openTab: openTab)
            }
        case .new(let provider):
            ProviderEditor(provider: provider, connectionID: nil, model: model, start: editorStart, select: select,
                           openTab: openTab)
        }
    }

    private func select(_ item: ProviderSidebarItem, connected: Bool) {
        if case .connection(let id) = item, connected { justConnected = id } else { justConnected = nil }
        selection = item
    }
}

/// The sidebar: each connected provider's accounts under its name, then the providers not connected yet.
struct ProvidersSidebar: View {
    let model: SpendModel
    @Binding var selection: ProviderSidebarItem

    var body: some View {
        SidebarPicker(groups: groups, selection: $selection, row: row)
    }

    private var groups: [SidebarGroup<ProviderSidebarItem>] {
        let connected = model.connected
        let available = ProviderID.allCases.filter { !connected.contains($0) }
        let accounts = connected.map { provider -> SidebarGroup<ProviderSidebarItem> in
            var items = model.connections(for: provider).map { ProviderSidebarItem.connection($0.id) }
            if selection == .new(provider) { items.append(.new(provider)) }
            return SidebarGroup(title: provider.info.name, items: items)
        }
        return accounts + [SidebarGroup(title: connected.isEmpty ? "Providers" : "Not connected",
                                        items: available.map { .new($0) })]
    }

    private func row(_ item: ProviderSidebarItem) -> ProviderRow {
        switch item {
        case .connection(let id):
            let record = model.connection(id)
            return ProviderRow(provider: record?.provider ?? .anthropic, title: record?.name ?? "",
                               status: model.status(id))
        case .new(let provider):
            if model.connected.contains(provider) {
                return ProviderRow(provider: provider, title: "New \(provider.info.name) account",
                                   status: ProviderStatus(light: .off, label: "Not connected", line: "Not connected yet"))
            }
            return ProviderRow(provider: provider, title: provider.info.name, status: model.status(provider))
        }
    }
}

/// One sidebar row: mark, name, and a status line with its light.
struct ProviderRow: View {
    let provider: ProviderID
    let title: String
    let status: ProviderStatus

    var body: some View {
        HStack(spacing: 9) {
            ProviderMark(provider: provider, serviceName: title)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 5) {
                    StatusLED(status.light.panel, size: 6)
                    Text(status.line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .help("\(title): \(status.line)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(status.line)")
    }
}
