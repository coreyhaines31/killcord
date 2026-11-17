import KillCordCore
import PanelKit
import SwiftUI

extension SignalLight {
    var panel: PanelStatus {
        switch self {
        case .go: .go
        case .caution: .caution
        case .stop: .stop
        case .off: .off
        }
    }
}

/// A provider's monogram on a small brushed key, the same material as PanelKit's tiles.
struct ProviderMark: View {
    let provider: ProviderID
    var size: CGFloat = 22

    @Environment(\.panelTheme) private var theme

    var body: some View {
        Text(String(provider.info.name.prefix(1)))
            .font(PanelFont.condensed(size * 0.58, .semibold))
            .foregroundStyle(theme.ink)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24)
                    .fill(LinearGradient(colors: theme.button2, startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(theme.button2Edge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A small outlined tag: "Dollar spend", "Hard stop".
struct Chip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .fixedSize()
    }
}

/// The top of a provider's detail: mark, name, status light, capability chip and one line of explanation.
struct ProviderHeader: View {
    let provider: ProviderID
    let title: String
    let status: PanelStatus
    let statusLabel: String
    let chips: [String]
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderMark(provider: provider, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(PanelFont.condensed(22, .semibold))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    StatusLight(status, statusLabel)
                }
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { Chip(text: $0) }
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}

/// The one privacy line under anything that takes a key.
struct PrivacyLine: View {
    let providerName: String

    var body: some View {
        Label {
            Text("Stored in your Keychain and sent only to \(providerName). Never paste a key into a chat or "
                + "AI agent.")
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// An outcome: a light, a short title, what happened and what to do next.
struct ResultBox<Actions: View>: View {
    let light: PanelStatus
    let title: String
    let message: String?
    let fix: String?
    @ViewBuilder var actions: () -> Actions

    @Environment(\.panelTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusLED(light, size: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                if let message {
                    Text(message).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let fix {
                    Text(fix).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions().padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(theme.color(for: light).opacity(light == .off ? 0.06 : 0.1),
                    in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
    }
}

extension ResultBox where Actions == EmptyView {
    init(light: PanelStatus, title: String, message: String?, fix: String?) {
        self.init(light: light, title: title, message: message, fix: fix) { EmptyView() }
    }
}

/// The number beside a setup step. Filled once the step is done.
struct StepNumber: View {
    let number: Int
    var isDone = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isDone ? Color.clear : Color.secondary.opacity(0.6), lineWidth: 1.2)
                .background(Circle().fill(isDone ? Color.green : Color.clear))
            if isDone {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            } else {
                Text("\(number)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityLabel(isDone ? "Step \(number), done" : "Step \(number)")
    }
}

/// A numbered step: number, title, a sentence, and whatever the step needs (a button, a field).
struct SetupStepRow<Content: View>: View {
    let number: Int
    let title: String
    let detail: String?
    var isDone = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StepNumber(number: number, isDone: isDone)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
