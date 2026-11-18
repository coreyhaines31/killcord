import Foundation

/// Made-up readings for demo mode and screenshots. Every surface that shows these labels them sample data.
public enum DemoData {
    /// Fixed ids, so demo renders are the same every time. Two Anthropic accounts show the provider subtotal.
    public static let ids: [String: UUID] = [
        "anthropic": "D0000000-0000-0000-0000-000000000001", "anthropic-2": "D0000000-0000-0000-0000-000000000002",
        "google": "D0000000-0000-0000-0000-000000000003", "openai": "D0000000-0000-0000-0000-000000000004",
        "vercel": "D0000000-0000-0000-0000-000000000005", "cloudflare": "D0000000-0000-0000-0000-000000000006",
        "twilio": "D0000000-0000-0000-0000-000000000007", "neon": "D0000000-0000-0000-0000-000000000008"
    ].mapValues { UUID(uuidString: $0)! }

    public static func registry(now: Date = Date()) -> ConnectionRegistry {
        let created = now.addingTimeInterval(-30 * 86400)
        func record(_ key: String, _ provider: ProviderID, name: String? = nil,
                    offset: Double = 0) -> ConnectionRecord {
            ConnectionRecord(id: ids[key]!, provider: provider, createdAt: created.addingTimeInterval(offset),
                             name: name)
        }
        return ConnectionRegistry(records: [
            record("anthropic", .anthropic), record("anthropic-2", .anthropic, name: "Client work", offset: 60),
            record("google", .google), record("openai", .openai), record("vercel", .vercel),
            record("cloudflare", .cloudflare), record("twilio", .twilio), record("neon", .neon)
        ])
    }

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
            provider: .cloudflare, connectionID: ids["cloudflare"]!,
            snapshot: snapshot(.cloudflare, today: nil, month: Decimal(string: "3.18"), minutesAgo: 70,
                               kind: .billingPeriod(start: now.addingTimeInterval(-12 * 86400)))
        )
        cloudflare.record(.rateLimited(retryAfter: 300), at: now.addingTimeInterval(-2 * 60))
        return [
            ProviderState(provider: .anthropic, connectionID: ids["anthropic"]!, snapshot: snapshot(
                .anthropic, today: Decimal(string: "18.42"), month: Decimal(string: "212.07"), minutesAgo: 3)),
            ProviderState(provider: .anthropic, connectionID: ids["anthropic-2"]!, snapshot: snapshot(
                .anthropic, today: Decimal(string: "6.10"), month: Decimal(string: "48.95"), minutesAgo: 3)),
            ProviderState(provider: .google, connectionID: ids["google"]!, snapshot: snapshot(
                .google, today: Decimal(string: "4.90"), month: Decimal(string: "61.33"), minutesAgo: 40,
                asOf: 7 * 60)),
            ProviderState(provider: .openai, connectionID: ids["openai"]!, snapshot: snapshot(
                .openai, today: Decimal(string: "2.15"), month: Decimal(string: "37.80"), minutesAgo: 3)),
            ProviderState(provider: .vercel, connectionID: ids["vercel"]!, snapshot: snapshot(
                .vercel, today: nil, month: Decimal(string: "24.00"), minutesAgo: 20)),
            cloudflare,
            ProviderState(provider: .twilio, connectionID: ids["twilio"]!, lastAttempt: now.addingTimeInterval(-60),
                          lastError: .invalidKey),
            ProviderState(provider: .neon, connectionID: ids["neon"]!, snapshot: snapshot(
                .neon, today: nil, month: nil, minutesAgo: 9, usage: [
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
