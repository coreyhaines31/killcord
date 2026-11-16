import Foundation

/// Made-up readings for demo mode and screenshots. Every surface that shows these labels them sample data.
public enum DemoData {
    public static func states(now: Date = Date()) -> [ProviderState] {
        func snapshot(_ provider: ProviderID, today: Decimal?, month: Decimal?, minutesAgo: Double,
                      kind: SpendSnapshot.MonthKind = .calendarMonth, usage: [UsageMetric] = [],
                      asOf: Double? = nil) -> SpendSnapshot {
            SpendSnapshot(provider: provider, today: today.map { Money($0) }, month: month.map { Money($0) },
                          monthKind: kind, usage: usage,
                          dataAsOf: asOf.map { now.addingTimeInterval(-$0 * 60) },
                          fetchedAt: now.addingTimeInterval(-minutesAgo * 60))
        }
        var cloudflare = ProviderState(
            provider: .cloudflare,
            snapshot: snapshot(.cloudflare, today: nil, month: Decimal(string: "3.18"), minutesAgo: 70,
                               kind: .billingPeriod(start: now.addingTimeInterval(-12 * 86400)))
        )
        cloudflare.record(.rateLimited(retryAfter: 300), at: now.addingTimeInterval(-2 * 60))
        return [
            ProviderState(provider: .anthropic, snapshot: snapshot(
                .anthropic, today: Decimal(string: "18.42"), month: Decimal(string: "212.07"), minutesAgo: 3)),
            ProviderState(provider: .google, snapshot: snapshot(
                .google, today: Decimal(string: "4.90"), month: Decimal(string: "61.33"), minutesAgo: 40,
                asOf: 7 * 60)),
            ProviderState(provider: .openai, snapshot: snapshot(
                .openai, today: Decimal(string: "2.15"), month: Decimal(string: "37.80"), minutesAgo: 3)),
            ProviderState(provider: .vercel, snapshot: snapshot(
                .vercel, today: nil, month: Decimal(string: "24.00"), minutesAgo: 20)),
            cloudflare,
            ProviderState(provider: .twilio, lastAttempt: now.addingTimeInterval(-60), lastError: .invalidKey),
            ProviderState(provider: .neon, snapshot: snapshot(.neon, today: nil, month: nil, minutesAgo: 9, usage: [
                UsageMetric(id: "compute_unit_seconds", name: "Compute", value: Decimal(string: "41.7")!,
                            unit: "CU-hours"),
                UsageMetric(id: "root_branch_bytes_month", name: "Root branch storage",
                            value: Decimal(string: "0.82")!, unit: "GB-months")
            ]))
        ]
    }

    public static func audit(now: Date = Date()) -> CapAuditState {
        var state = CapAuditState()
        state.mark("anthropic.org-spend-limit", .done(at: now.addingTimeInterval(-3 * 86400)))
        state.mark("supabase.spend-cap", .done(at: now.addingTimeInterval(-40 * 86400)))
        state.record([
            CapVerification(capID: OpenAIProvider.hardLimitCapID,
                            status: .on("OpenAI reports a hard limit of $100.00 a month."), checkedAt: now),
            CapVerification(capID: GoogleCloudProvider.spendCapID,
                            status: .off("Google reports no spend cap budget on this billing account."),
                            checkedAt: now)
        ])
        return state
    }
}
