import Foundation
import KillCordCore

// Prints what Kill Cord knows without keys or network: each provider's capability, the caps catalog, and
// the sample spend demo mode shows.
let now = Date()
for provider in ProviderID.allCases {
    let info = provider.info
    print("\(info.name): \(info.capability.summary)")
    print("  Lag: \(info.lag.note)")
    for control in CapsCatalog.controls(for: provider) {
        print("  [\(control.enforcement.label), \(control.verification.rawValue)] \(control.name)")
        print("    \(control.consoleURL.absoluteString)")
    }
}

print("\nSample data:")
let context = FreshnessContext(now: now, launchedAt: now.addingTimeInterval(-3600), interval: 15 * 60)
let summary = SpendSummary(states: DemoData.states(now: now), context: context)
for row in summary.rows {
    print("  \(row.provider.info.name): today \(SpendText.amount(row.today)), month \(SpendText.amount(row.month)), "
        + SpendText.freshness(row.freshness, now: now))
}
print("  Total today \(MoneyText.string(summary.today)), this month \(MoneyText.string(summary.month))")
