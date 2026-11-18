import Foundation
@testable import KillCordCore
import Testing

func day(_ text: String) -> Date { ManualPlan.day(text)! }

@Suite struct ManualPlanTests {
    @Test func readsWhatWasTypedAndRollsTheRenewalForward() throws {
        // Entered as Nov 3; it's Nov 15, so the next renewal is Dec 3.
        let plan = try ManualPlan(FakeKeys.credentials(.manual), now: testNow)
        #expect(plan.plan == "Starter")
        #expect(plan.price == Money(Decimal(string: "49.25")!))
        #expect(plan.renewsOn == day("2026-12-03"))
        #expect(plan.allowance == 12345 && plan.allowanceUnit == "credits")
        #expect(plan.remindDaysBefore == 3)
        #expect(ManualText.summary(plan, now: testNow) == "Starter · $49.25 a month · Renews Dec 3")
        #expect(ManualText.allowance(plan) == "12,345 credits a month included")
    }

    @Test func monthEndsAndYearsStayOnTheirDay() {
        #expect(ManualPlan.next(day("2026-01-31"), period: .monthly, onOrAfter: day("2026-02-15")) == day("2026-02-28"))
        #expect(ManualPlan.next(day("2026-01-31"), period: .monthly, onOrAfter: day("2026-03-02")) == day("2026-03-31"))
        #expect(ManualPlan.next(day("2025-06-01"), period: .yearly, onOrAfter: day("2026-07-01")) == day("2027-06-01"))
        // Today counts as on or after.
        #expect(ManualPlan.next(day("2026-11-15"), period: .monthly, onOrAfter: testNow) == day("2026-11-15"))
    }

    @Test func refusesWhatItCantRead() {
        for (field, value) in [("renewsOn", "Dec 3"), ("renewsOn", "2026-13-40"), ("price", "lots"), ("allowance", "-5")] {
            var values = FakeKeys.credentials(.manual).allValuesForTests
            values[field] = value
            #expect(throws: SpendError.self, "\(field)=\(value)") {
                try ManualPlan(ProviderCredentials(provider: .manual, values: values), now: testNow)
            }
        }
        let priced = FakeKeys.credentials(.manual).allValuesForTests.merging(["price": "$1,200.50"]) { $1 }
        #expect((try? ManualPlan(ProviderCredentials(provider: .manual, values: priced), now: testNow))?.price
            == Money(Decimal(string: "1200.5")!))
    }

    @Test func neverTouchesTheNetworkAndNeverCountsAsSpend() async throws {
        let snapshot = try await SpendProviders.make(.manual, http: MockHTTPClient { _ in
            Issue.record("a manual entry made a request")
            return HTTPResponse(status: 500)
        }).fetchSpend(FakeKeys.credentials(.manual), now: testNow)
        #expect(snapshot.manual != nil && snapshot.today == nil && snapshot.month == nil && snapshot.balance == nil)
        let state = ProviderState(provider: .manual, connectionID: .of(.manual), snapshot: snapshot)
        let context = FreshnessContext(now: testNow, launchedAt: testNow.addingTimeInterval(-60), lastWake: nil,
                                       isAsleep: false, isOnline: true, interval: 900)
        let summary = SpendSummary(states: [state, reading(.anthropic, today: "2", month: "3")], context: context)
        #expect(summary.today.amount(in: .usd) == Money(2))
        #expect(summary.missingToday.isEmpty && summary.missingMonth.isEmpty && summary.isComplete)
    }

    @Test func itsStatusSaysNotLiveEnteredByYou() throws {
        let state = ProviderState(provider: .manual, connectionID: .of(.manual), snapshot: SpendSnapshot(
            provider: .manual, today: nil, month: nil, manual: try ManualPlan(FakeKeys.credentials(.manual), now: testNow),
            fetchedAt: testNow))
        let status = ProviderStatus.of(.manual, isConnected: true, state: state, freshness: .live(checkedAt: testNow),
                                       now: testNow)
        #expect(status.light == .off)
        #expect(status.label == "Entered by you")
        #expect(ProviderStatus.of(.manual, isConnected: true, state: nil, freshness: .neverChecked).line
            == "Not live: entered by you")
        #expect(ProviderID.manual.info.capabilityLabel == "Entered by you")
    }
}

@Suite struct RenewalReminderTests {
    let planner = ThresholdPlanner()

    func state(renewal: String, remind: Int? = 3, at now: Date) -> ProviderState {
        ProviderState(provider: .manual, connectionID: .of(.manual), snapshot: SpendSnapshot(
            provider: .manual, today: nil, month: nil,
            manual: ManualPlan(plan: "Starter", price: Money(49), renewsOn: day(renewal), remindDaysBefore: remind),
            fetchedAt: now))
    }

    @Test func remindsOncePerRenewalInsideTheWindow() {
        let key = "\(UUID.of(.manual).uuidString)|renewal|2026-11-18|3"
        // Nov 14: four days out, too early.
        let early = day("2026-11-14")
        let (none, state0) = planner.plan(states: [state(renewal: "2026-11-18", at: early)],
                                          names: [.of(.manual): "Truelist"], thresholds: .init(), state: .init(), now: early)
        #expect(none.isEmpty)
        // Nov 15: three days out. One reminder, kept after the day ends.
        let (first, state1) = planner.plan(states: [state(renewal: "2026-11-18", at: testNow)],
                                           names: [.of(.manual): "Truelist"], thresholds: .init(), state: state0,
                                           now: testNow)
        #expect(first.map(\.id) == [key])
        #expect(first.first?.title == "Truelist renews Nov 18")
        #expect(first.first?.body == "Starter, $49.00 a month. From the plan you entered in Kill Cord.")
        let nextDay = day("2026-11-16")
        let (quiet, state2) = planner.plan(states: [state(renewal: "2026-11-18", at: nextDay)], thresholds: .init(),
                                           state: state1, now: nextDay)
        #expect(quiet.isEmpty)
        #expect(state2.fired.contains(key))
        // After the renewal the key is dropped, and next month's renewal reminds again.
        let december = day("2026-12-15")
        let (again, state3) = planner.plan(states: [state(renewal: "2026-12-18", at: december)], thresholds: .init(),
                                           state: state2, now: december)
        #expect(again.map(\.id) == ["\(UUID.of(.manual).uuidString)|renewal|2026-12-18|3"])
        #expect(!state3.fired.contains(key))
    }

    @Test func noReminderWhenTurnedOff() {
        let (alerts, _) = planner.plan(states: [state(renewal: "2026-11-16", remind: nil, at: testNow)],
                                       thresholds: .init(), state: .init(), now: testNow)
        #expect(alerts.isEmpty)
    }
}

@Suite struct ManualTextTests {
    @Test func renewalWords() {
        func plan(_ text: String) -> ManualPlan { ManualPlan(renewsOn: day(text)) }
        #expect(ManualText.renewal(plan("2026-11-15"), now: testNow) == "Renews today")
        #expect(ManualText.renewal(plan("2026-11-16"), now: testNow) == "Renews tomorrow")
        #expect(ManualText.renewal(plan("2026-12-03"), now: testNow) == "Renews Dec 3")
        #expect(ManualText.renewalDay(plan("2026-11-16"), now: testNow) == "Tomorrow")
    }
}
