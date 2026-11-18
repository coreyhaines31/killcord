import AppKit
import SwiftUI

/// A settings sidebar whose rows are plain buttons: one click selects, the arrow keys move, and VoiceOver
/// hears which row is selected. It replaces `List(selection:)`, whose rows were identified by
/// `ProviderID.id` (a String) while the selection was a `ProviderID?`, so clicks never reached the binding.
struct SidebarPicker<Item: Hashable, Row: View>: View {
    typealias Group = SidebarGroup<Item>

    let groups: [Group]
    @Binding var selection: Item
    @ViewBuilder let row: (Item) -> Row
    @FocusState private var isFocused: Bool

    private var items: [Item] { groups.flatMap(\.items) }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        if !group.items.isEmpty {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.items, id: \.self) { item in
                                button(item).id(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onMoveCommand { direction in
                move(direction)
                scroller.scrollTo(selection)
            }
        }
        .background(SidebarMaterial())
    }

    private func button(_ item: Item) -> some View {
        let isSelected = item == selection
        return Button {
            selection = item
            isFocused = true
        } label: {
            row(item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(isFocused ? 0.28 : 0.16) : .clear)
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func move(_ direction: MoveCommandDirection) {
        guard let index = items.firstIndex(of: selection) else { return }
        switch direction {
        case .up where index > 0: selection = items[index - 1]
        case .down where index < items.count - 1: selection = items[index + 1]
        default: break
        }
    }
}

/// A titled run of sidebar rows. The title is hidden when the group is empty.
struct SidebarGroup<Item: Hashable> {
    let title: String
    let items: [Item]
}

/// The standard sidebar material behind the rows.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
