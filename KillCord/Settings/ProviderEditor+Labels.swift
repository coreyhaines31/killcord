import KillCordCore
import SwiftUI

/// The words that change with the kind of connection: built-in, custom, or entered by hand.
extension ProviderEditor {
    func pasteTitle(replacing: Bool) -> String {
        if replacing { return "Paste the new key. Leave a secret empty to keep the saved one." }
        let fields = provider.info.fields
        if fields.count == 1, let field = fields.first {
            // "Admin API key" reads "admin API key"; "API key" keeps its acronym.
            let label = field.label.dropFirst().first?.isLowercase == true
                ? field.label.prefix(1).lowercased() + field.label.dropFirst() : field.label
            return "Paste the \(label) here"
        }
        return "Fill in these fields"
    }

    /// Who the key is sent to, for the privacy line. A custom service is named as the person typed it.
    func privacyName(typed: String?) -> String {
        guard provider == .custom else { return provider.info.name }
        let name = typed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "the address above" : name
    }

    var sectionTitle: String {
        if provider == .manual { return "Plan" }
        let capability = provider.info.capability
        return capability.showsBalance && !capability.showsMoney ? "Balance" : "Spend"
    }

    var anotherTitle: String {
        switch provider {
        case .custom: "Add Another Custom Service…"
        case .manual: "Add Another Manual Entry…"
        default: "Add Another \(provider.info.name) Account…"
        }
    }

    /// Where a custom connection's numbers come from and how often it's asked.
    func customNote(_ config: CustomConfig) -> String {
        let minutes = Int(config.interval / 60)
        var note = "Read from \(config.url.host ?? "your address"), at most every \(minutes) minutes. Kill Cord "
            + "can't verify these numbers, so compare them with the service's own dashboard."
        if config.checksCostMoney { note += " Each check costs money on this service." }
        return note
    }
}
