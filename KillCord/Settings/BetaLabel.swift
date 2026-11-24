import KillCordCore
import SwiftUI

/// The quiet "Beta" tag on a provider that hasn't been verified with a live account. Grey like every other
/// chip: the lights are the only colour in the family. The tooltip says why.
struct BetaChip: View {
    var compact = false

    var body: some View {
        Text(ProviderVerification.betaLabel)
            .font(compact ? .system(size: 9, weight: .medium) : .caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 4 : 7)
            .padding(.vertical, compact ? 0 : 2)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1))
            .fixedSize()
            .help(ProviderVerification.betaDetail)
            .accessibilityLabel("Beta. \(ProviderVerification.betaDetail)")
    }
}

/// The line under an error from a beta provider, with a plain link to the GitHub issues page.
struct BetaReportLine: View {
    var fontSize: CGFloat?

    var body: some View {
        Text(Self.text)
            .font(fontSize.map { .system(size: $0) } ?? .callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    static var text: AttributedString {
        var text = AttributedString(ProviderVerification.betaErrorLine + ".")
        if let range = text.range(of: "report it") {
            text[range].link = ProviderVerification.issuesURL
        }
        return text
    }
}
