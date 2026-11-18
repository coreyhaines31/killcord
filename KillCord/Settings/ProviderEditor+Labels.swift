import KillCordCore
import SwiftUI

/// The words that change with the kind of connection: built-in, custom, or entered by hand.
extension ProviderEditor {
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
