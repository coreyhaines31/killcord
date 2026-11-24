import Foundation
@testable import KillCordCore
import Testing

func reading(_ provider: ProviderID, today: String?, month: String?, at: Date = testNow,
             estimate: Bool = false, number: Int = 1) -> ProviderState {
    ProviderState(provider: provider, connectionID: .of(provider, number), snapshot: SpendSnapshot(
        provider: provider, today: today.map(usd), month: month.map(usd), isEstimate: estimate, fetchedAt: at
    ))
}

@Suite struct ThresholdPlannerTests {
    let planner = ThresholdPlanner()
    let anthropic = UUID.of(.anthropic).uuidString
    let thresholds = SpendThresholds(
        perConnection: [.of(.anthropic): .init(daily: 50, monthly: 500)],
        total: .init(daily: 60, monthly: 1000)
    )

    @Test func firesOncePerThresholdPerPeriod() {
        let (first, state) = planner.plan(states: [reading(.anthropic, today: "52.10", month: "300")],
                                          thresholds: thresholds, state: .init(), now: testNow)
        #expect(first.map(\.id) == ["\(anthropic)|day|2026-11-15|50"])
        #expect(first.first?.title == "Anthropic spent $52.10 today")
        #expect(first.first?.body.hasPrefix("That's past your $50.00 daily alert. Last checked") == true)
        let (again, state2) = planner.plan(states: [reading(.anthropic, today: "80", month: "320")],
                                           thresholds: thresholds, state: state, now: testNow.addingTimeInterval(600))
        // The provider's daily alert already fired; the total crossed $60 now.
        #expect(again.map(\.id) == ["total|day|2026-11-15|60"])
        let (quiet, _) = planner.plan(states: [reading(.anthropic, today: "90", month: "330")],
                                      thresholds: thresholds, state: state2, now: testNow.addingTimeInterval(1200))
        #expect(quiet.isEmpty)
    }

    @Test func aNewDayCanFireAgain() {
        let (_, state) = planner.plan(states: [reading(.anthropic, today: "52", month: "52")],
                                      thresholds: thresholds, state: .init(), now: testNow)
        let tomorrow = testNow.addingTimeInterval(86400)
        let (alerts, next) = planner.plan(states: [reading(.anthropic, today: "51", month: "103", at: tomorrow)],
                                          thresholds: thresholds, state: state, now: tomorrow)
        #expect(alerts.map(\.id) == ["\(anthropic)|day|2026-11-16|50"])
        // Yesterday's key is pruned.
        #expect(!next.fired.contains("\(anthropic)|day|2026-11-15|50"))
    }

    @Test func yesterdaysReadingDoesntCountForToday() {
        let yesterday = testNow.addingTimeInterval(-86400)
        let (alerts, _) = planner.plan(states: [reading(.anthropic, today: "99", month: "99", at: yesterday)],
                                       thresholds: thresholds, state: .init(), now: testNow)
        #expect(alerts.isEmpty)
    }

    @Test func changingTheThresholdCanFireAgain() {
        let (_, state) = planner.plan(states: [reading(.anthropic, today: "52", month: "52")],
                                      thresholds: thresholds, state: .init(), now: testNow)
        var lower = thresholds
        lower.perConnection[.of(.anthropic)] = .init(daily: 40)
        let (alerts, _) = planner.plan(states: [reading(.anthropic, today: "52", month: "52")],
                                       thresholds: lower, state: state, now: testNow)
        #expect(alerts.map(\.id) == ["\(anthropic)|day|2026-11-15|40"])
    }

    @Test func monthlyAndTotals() {
        let states = [reading(.anthropic, today: "10", month: "600"), reading(.openai, today: "5", month: "450")]
        let (alerts, _) = planner.plan(states: states, thresholds: thresholds, state: .init(), now: testNow)
        #expect(alerts.map(\.id) == ["\(anthropic)|month|2026-11|500", "total|month|2026-11|1000"])
        #expect(alerts.last?.title == "All providers spent $1,050.00 this month")
    }

    @Test func estimatesAreLabeledAndOtherCurrenciesIgnored() {
        let estimate = reading(.anthropic, today: "55", month: "55", estimate: true)
        let (alerts, _) = planner.plan(states: [estimate], thresholds: thresholds, state: .init(), now: testNow)
        #expect(alerts.first?.title == "Anthropic spent $55.00 (estimate) today")

        let euros = ProviderState(provider: .anthropic, connectionID: .of(.anthropic), snapshot: SpendSnapshot(
            provider: .anthropic, today: Money(decimal("999"), Currency("EUR")), month: nil, fetchedAt: testNow))
        let (none, _) = planner.plan(states: [euros], thresholds: thresholds, state: .init(), now: testNow)
        #expect(none.isEmpty)
    }

    @Test func eachConnectionHasItsOwnAlertAndNameAndTheProviderTotalAddsThemUp() {
        let second = UUID.of(.anthropic, 2)
        let limits = SpendThresholds(perConnection: [.of(.anthropic): .init(daily: 50), second: .init(daily: 50)],
                                     providerTotals: [.anthropic: .init(daily: 70)])
        let states = [reading(.anthropic, today: "40", month: "40"),
                      reading(.anthropic, today: "55", month: "55", number: 2)]
        let (alerts, state) = planner.plan(states: states, names: [.of(.anthropic): "Anthropic", second: "Client work"],
                                           thresholds: limits, state: .init(), now: testNow)
        #expect(alerts.map(\.id) == ["\(second.uuidString)|day|2026-11-15|50", "anthropic|day|2026-11-15|70"])
        #expect(alerts.map(\.title) == ["Client work spent $55.00 today", "All Anthropic accounts spent $95.00 today"])
        let (again, _) = planner.plan(states: states, thresholds: limits, state: state, now: testNow)
        #expect(again.isEmpty)
    }

    @Test func noThresholdsNoAlerts() {
        let (alerts, _) = planner.plan(states: [reading(.anthropic, today: "1000", month: "9000")],
                                       thresholds: SpendThresholds(), state: .init(), now: testNow)
        #expect(alerts.isEmpty)
    }
}

@Suite struct SpendSummaryTests {
    let context = FreshnessContext(now: testNow, launchedAt: testNow.addingTimeInterval(-3600), interval: 15 * 60)

    @Test func totalsAndSaysWhatsMissing() {
        let states = [
            reading(.anthropic, today: "12.35", month: "34.2052"),
            reading(.openai, today: "1.0601", month: "13.8332"),
            reading(.vercel, today: nil, month: "124.72"),
            ProviderState(provider: .twilio, connectionID: .of(.twilio), lastAttempt: testNow, lastError: .invalidKey),
            ProviderState(provider: .neon, connectionID: .of(.neon), snapshot: SpendSnapshot(
                provider: .neon, today: nil, month: nil,
                                                                   fetchedAt: testNow))
        ]
        let summary = SpendSummary(states: states, context: context)
        #expect(summary.today.amount(in: .usd) == usd("13.4101"))
        #expect(summary.month.amount(in: .usd) == usd("172.7584"))
        #expect(summary.missingToday == [.of(.vercel), .of(.twilio)])
        #expect(summary.missingMonth == [.of(.twilio)])
        #expect(summary.failing == [.of(.twilio)])
        #expect(summary.names(summary.missingToday) == ["Vercel", "Twilio"])
        #expect(!summary.isComplete)
        // Neon reports usage, so it's never counted as missing money.
        #expect(!summary.missingToday.contains(.of(.neon)))
        #expect(summary.rows.map(\.provider) == [.anthropic, .openai, .vercel, .twilio, .neon])
    }

    @Test func staleNumbersAreFlagged() {
        let old = reading(.anthropic, today: "5", month: "50", at: testNow.addingTimeInterval(-2 * 3600))
        let summary = SpendSummary(states: [old], context: context)
        #expect(summary.stale == [.of(.anthropic)])
        #expect(summary.today.amount(in: .usd) == usd("5"))
        #expect(SpendText.menuBar(summary, period: .today) == "$5.00*")
    }

    @Test func lastMonthsReadingDoesntCountThisMonth() {
        let lastMonth = reading(.anthropic, today: "5", month: "50", at: ISO8601.date("2026-10-31T20:00:00Z")!)
        let summary = SpendSummary(states: [lastMonth], context: context)
        #expect(summary.month.isEmpty)
        #expect(summary.missingMonth == [.of(.anthropic)])
    }

    @Test func menuBarText() {
        let summary = SpendSummary(states: [reading(.anthropic, today: "12.35", month: "1234")], context: context)
        #expect(SpendText.menuBar(summary, period: .today) == "$12.35")
        #expect(SpendText.menuBar(summary, period: .month) == "$1.2k")
        #expect(SpendText.menuBar(SpendSummary(states: [], context: context), period: .today) == "")
    }

    @Test func demoDataIsCoherent() {
        let states = DemoData.states(now: testNow)
        let summary = SpendSummary(states: states, context: FreshnessContext(
            now: testNow, launchedAt: testNow.addingTimeInterval(-3600), interval: 15 * 60))
        #expect(summary.rows.count == states.count)
        #expect(summary.today.amount(in: .usd) == usd("31.57"))
        #expect(!summary.failing.isEmpty)
        let names = DemoData.registry(now: testNow).names
        #expect(Set(states.map(\.connectionID)) == Set(names.keys))
    }

    @Test func groupsConnectionsByProviderWithASubtotal() {
        let states = [reading(.openai, today: "1", month: "2"),
                      reading(.anthropic, today: "10", month: "100"),
                      reading(.anthropic, today: nil, month: "50", number: 2)]
        let summary = SpendSummary(states: states, names: [.of(.anthropic, 2): "Client work"], context: context)
        #expect(summary.rows.map(\.name) == ["Anthropic", "Client work", "OpenAI"])
        #expect(summary.groups.map(\.provider) == [.anthropic, .openai])
        let anthropic = summary.groups[0]
        #expect(anthropic.rows.count == 2)
        #expect(anthropic.today.amount(in: .usd) == usd("10"))
        #expect(anthropic.month.amount(in: .usd) == usd("150"))
        #expect(summary.missingToday == [.of(.anthropic, 2)])
        #expect(summary.today.amount(in: .usd) == usd("11"))
    }
}

@Suite struct CapsCatalogTests {
    /// Manual entries have no API and no caps Kill Cord could walk through.
    @Test(arguments: ProviderID.allCases.filter { !$0.info.capability.showsBalance && $0 != .manual })
    func everySpendProviderHasAtLeastOneCap(_ provider: ProviderID) {
        #expect(!CapsCatalog.controls(for: provider).isEmpty)
    }

    /// A prepaid balance stops at zero on its own. Extra caps are listed only where the provider documents one.
    @Test func balanceProvidersListOnlyDocumentedCaps() {
        let withCaps = ProviderID.allCases.filter {
            $0.info.capability.showsBalance && !CapsCatalog.controls(for: $0).isEmpty
        }
        let more = Set(ProviderInfo.moreBalanceProviders.map(\.id))
        let batch3 = Set(ProviderInfo.batch3Providers.map(\.id))
        #expect(withCaps.filter { !more.contains($0) && !batch3.contains($0) }
            == [.openrouter, .monid, .fal, .elevenlabs, .xai, .apify, .tavily, .runway, .brightdata])
        #expect(withCaps.filter { more.contains($0) } == [.runpod, .xapi, .bfl, .telnyx, .luma])
        #expect(withCaps.filter { batch3.contains($0) } == [.moonshot, .exa, .scrapingbee, .scrapfly, .kie, .bland])
    }

    @Test func everyCapHasHTTPSLinksStepsAndAUniqueID() {
        let ids = CapsCatalog.controls.map(\.id)
        #expect(Set(ids).count == ids.count)
        for control in CapsCatalog.controls {
            #expect(control.consoleURL.scheme == "https", "\(control.id) console")
            #expect(control.docURL.scheme == "https", "\(control.id) docs")
            #expect(control.consoleURL.host != nil && control.docURL.host != nil)
            #expect(!control.steps.isEmpty)
            #expect(control.id.hasPrefix(control.provider.rawValue + "."))
            for text in [control.name, control.summary, control.caveat ?? ""] + control.steps {
                #expect(!text.contains("—"), "Em dash in \(control.id)")
            }
        }
    }

    @Test func eachMoneyProviderHasAHardOrPartialStopOrSaysThereIsNone() {
        for provider in ProviderID.allCases where !provider.info.capability.showsBalance && provider != .manual {
            let controls = CapsCatalog.controls(for: provider)
            let stops = controls.filter { $0.enforcement != .alertOnly }
            if stops.isEmpty {
                // Twilio is the only one with no native stop, and its caveat says so.
                #expect(provider == .twilio)
                #expect(controls.contains { $0.caveat?.contains("no native hard spend cap") == true })
            }
        }
    }

    @Test func apiVerifiableCapsMatchWhatTheAdaptersReport() {
        let verifiable = Set(CapsCatalog.controls.filter { $0.verification == .api }.map(\.id))
        #expect(verifiable == [
            OpenAIProvider.hardLimitCapID, GoogleCloudProvider.spendCapID, GoogleCloudProvider.budgetAlertCapID,
            CloudflareProvider.spendLimitCapID, TwilioProvider.triggerCapID, NeonProvider.thresholdCapID,
            ApifyProvider.usageLimitCapID, TelnyxProvider.autoRechargeCapID
        ])
        // Anthropic can't be checked over the API for Console organizations.
        #expect(CapsCatalog.controls(for: .anthropic).allSatisfy { $0.verification == .selfReported })
    }

    @Test func providerInfoIsCompleteAndHonest() {
        for provider in ProviderID.allCases {
            let info = provider.info
            #expect(info.consoleURL.scheme == "https")
            #expect(info.keyURL.map { $0.scheme == "https" } ?? true)
            #expect(info.minimumRefreshInterval >= 5 * 60)
            #expect(!info.lag.note.contains("—"))
            #expect(info.connects == (provider != .supabase))
        }
        #expect(ProviderID.anthropic.info.keyPowerWarning?.contains("no read-only key") == true)
        #expect(ProviderID.openai.info.keyPowerWarning != nil)
        #expect(ProviderID.neon.info.capability == .usageUnitsOnly)
        guard case .requiresSetup = ProviderID.google.info.capability else {
            Issue.record("Google should need setup"); return
        }
    }
}

@Suite struct CapAuditStateTests {
    let hardLimit = CapsCatalog.control(OpenAIProvider.hardLimitCapID)!
    let anthropicLimit = CapsCatalog.control("anthropic.org-spend-limit")!

    @Test func selfReportedMarksAskForARecheckAfterAMonth() {
        var state = CapAuditState()
        #expect(state.status(of: anthropicLimit, now: testNow) == .notDone)
        state.mark(anthropicLimit.id, .done(at: testNow))
        #expect(state.status(of: anthropicLimit, now: testNow) == .markedDone(at: testNow, recheck: false))
        let later = testNow.addingTimeInterval(31 * 86400)
        #expect(state.status(of: anthropicLimit, now: later) == .markedDone(at: testNow, recheck: true))
        #expect(state.dueForRecheck(now: later).map(\.id) == [anthropicLimit.id])
        #expect(state.status(of: anthropicLimit, now: later).needsAttention)
    }

    @Test func anAPIReadingOverridesAnOlderMark() {
        var state = CapAuditState()
        state.mark(hardLimit.id, .done(at: testNow.addingTimeInterval(-3600)))
        state.record([CapVerification(capID: hardLimit.id, status: .off("none"), checkedAt: testNow)])
        #expect(state.status(of: hardLimit, now: testNow) == .verifiedOff("none", at: testNow))
        #expect(!state.status(of: hardLimit, now: testNow).isDone)
    }

    @Test func aMarkAfterTheReadingWinsUntilTheNextCheck() {
        var state = CapAuditState()
        state.record([CapVerification(capID: hardLimit.id, status: .off("none"), checkedAt: testNow)])
        state.mark(hardLimit.id, .done(at: testNow.addingTimeInterval(60)))
        guard case .markedDone = state.status(of: hardLimit, now: testNow.addingTimeInterval(120)) else {
            Issue.record("Expected the newer mark"); return
        }
        state.record([CapVerification(capID: hardLimit.id, status: .on("set"), checkedAt: testNow.addingTimeInterval(300))])
        #expect(state.status(of: hardLimit, now: testNow) == .verifiedOn("set", at: testNow.addingTimeInterval(300)))
    }

    @Test func enforcedIsDoneButVisible() {
        var state = CapAuditState()
        state.record([CapVerification(capID: hardLimit.id, status: .enforced("stopped"), checkedAt: testNow)])
        #expect(state.status(of: hardLimit, now: testNow) == .enforced("stopped", at: testNow))
    }

    @Test func notApplicableCountsAsHandled() {
        var state = CapAuditState()
        state.mark(hardLimit.id, .notApplicable(at: testNow))
        state.record([CapVerification(capID: hardLimit.id, status: .off("none"), checkedAt: testNow.addingTimeInterval(60))])
        #expect(state.status(of: hardLimit, now: testNow) == .notApplicable)
    }

    @Test func progressCountsPerProvider() {
        var state = CapAuditState()
        #expect(state.progress(for: .anthropic, now: testNow) == .init(done: 0, total: 2, needsAttention: 2))
        state.mark("anthropic.org-spend-limit", .done(at: testNow))
        state.mark("anthropic.workspace-limit", .done(at: testNow))
        #expect(state.progress(for: .anthropic, now: testNow).isComplete)
    }

    @Test func savesAndLoads() throws {
        var state = CapAuditState()
        state.mark("supabase.spend-cap", .done(at: testNow))
        state.record([CapVerification(capID: hardLimit.id, status: .on("x"), checkedAt: testNow)])
        let decoded = try JSONDecoder().decode(CapAuditState.self, from: try JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}

@Suite struct SpendTextTests {
    let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
     }()

    @Test func times() {
        #expect(SpendText.time(ISO8601.date("2026-11-15T23:42:00Z")!, now: testNow, calendar: calendar) == "11:42p")
        #expect(SpendText.time(ISO8601.date("2026-11-15T09:00:00Z")!, now: testNow, calendar: calendar) == "9a")
        #expect(SpendText.time(ISO8601.date("2026-11-14T12:05:00Z")!, now: testNow, calendar: calendar) == "Sat 12:05p")
        #expect(SpendText.time(ISO8601.date("2026-11-01T12:05:00Z")!, now: testNow, calendar: calendar) == "Nov 1")
    }

    @Test func durations() {
        #expect(SpendText.duration(30) == "30s")
        #expect(SpendText.duration(45 * 60) == "45m")
        #expect(SpendText.duration(3 * 3600 + 7 * 60) == "3h 7m")
        #expect(SpendText.duration(64 * 3600) == "2d 16h")
    }

    @Test func amountsAndPeriods() {
        #expect(SpendText.amount(nil) == "Not reported yet")
        #expect(SpendText.amount(usd("3.5"), isEstimate: true) == "$3.50 (estimate)")
        #expect(SpendText.monthLabel(.calendarMonth) == "This month")
        #expect(SpendText.monthLabel(.billingPeriod(start: ISO8601.date("2026-11-03T00:00:00Z")!))
            == "Billing period from Nov 3")
        #expect(SpendText.usage(UsageMetric(id: "c", name: "Compute", value: decimal("2.5"), unit: "CU-hours"))
            == "2.5 CU-hours")
    }
}
