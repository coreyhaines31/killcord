import Foundation
import KillCordCore

extension SpendModel {
    /// Providers the person uses: connected ones, plus any they've marked a cap for (Supabase has nothing to
    /// connect, so marking its cap is how it joins the audit).
    var auditProviders: [ProviderID] {
        ProviderID.allCases.filter { provider in
            let controls = capControls(for: provider)
            guard !controls.isEmpty else { return false }
            return connected.contains(provider) || controls.contains { audit.marks[$0.id] != nil }
        }
    }

    var capsNeedingAttention: Int {
        auditProviders.reduce(0) { $0 + capProgress(for: $1).needsAttention }
    }

    /// A provider's native caps. For manual entries, the caps of the presets they're named after.
    func capControls(for provider: ProviderID) -> [CapControl] {
        CapsCatalog.controls(for: provider, manualServices: connections(for: .manual).map(\.name))
    }

    func capProgress(for provider: ProviderID, now: Date = Date()) -> CapAuditState.Progress {
        audit.progress(of: capControls(for: provider), now: now)
    }
}
