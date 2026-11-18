import Foundation
@testable import KillCordCore
import Testing

@Suite struct BalanceAlertTests {
    let planner = ThresholdPlanner()
    let id = UUID.of(.openai)
    var thresholds: SpendThresholds { SpendThresholds(perConnection: [id: .init(lowBalance: 10)]) }
    var key: String { "\(id.uuidString)|balance|low|10" }

    @Test func firesOnceWhenItCrossesAndAgainOnlyAfterATopUp() {
        let (first, state) = planner.plan(states: [withBalance(.openai, .usd(Decimal(string: "9.5")!))],
                                          names: [id: "Credits"], thresholds: thresholds, state: .init(), now: testNow)
        #expect(first.map(\.id) == [key])
        #expect(first.first?.title == "Credits is down to $9.50")
        #expect(first.first?.body.hasPrefix("That's at or below your $10.00 low-balance alert.") == true)
        // Still low a day later: quiet, and the key survives the end of the day.
        let later = testNow.addingTimeInterval(86400)
        let (quiet, stillLow) = planner.plan(states: [withBalance(.openai, .usd(3), at: later)],
                                             thresholds: thresholds, state: state, now: later)
        #expect(quiet.isEmpty)
        #expect(stillLow.fired.contains(key))
        // Topped up: re-armed. Then it drops again and alerts again.
        let (none, toppedUp) = planner.plan(states: [withBalance(.openai, .usd(50), at: later)],
                                            thresholds: thresholds, state: stillLow, now: later)
        #expect(none.isEmpty)
        #expect(!toppedUp.fired.contains(key))
        let (again, _) = planner.plan(states: [withBalance(.openai, .usd(8), at: later)],
                                      thresholds: thresholds, state: toppedUp, now: later)
        #expect(again.map(\.id) == [key])
    }

    @Test func aFailedOrMissingReadingKeepsTheKey() {
        let (_, state) = planner.plan(states: [withBalance(.openai, .usd(2))], thresholds: thresholds, state: .init(),
                                      now: testNow)
        var failed = ProviderState(provider: .openai, connectionID: id)
        failed.record(.network, at: testNow)
        let (none, next) = planner.plan(states: [failed], thresholds: thresholds, state: state, now: testNow)
        #expect(none.isEmpty)
        #expect(next.fired.contains(key))
        let (_, absent) = planner.plan(states: [], thresholds: thresholds, state: state, now: testNow)
        #expect(absent.fired.contains(key))
    }

    @Test func unitsAlertInTheirOwnUnitAndAChangedLimitIsANewAlert() {
        let credits = Balance(remaining: 450, unit: .units("credits"), kind: .allowance)
        let low = SpendThresholds(perConnection: [id: .init(lowBalance: 500)])
        let (alerts, state) = planner.plan(states: [withBalance(.openai, credits)], thresholds: low, state: .init(),
                                           now: testNow)
        #expect(alerts.first?.title == "OpenAI is down to 450 credits")
        let lower = SpendThresholds(perConnection: [id: .init(lowBalance: 400)])
        let (none, next) = planner.plan(states: [withBalance(.openai, credits)], thresholds: lower, state: state,
                                        now: testNow)
        #expect(none.isEmpty)
        // The old limit's key is dropped once that limit is gone.
        #expect(next.fired.isEmpty)
    }

    @Test func noLimitMeansNoAlert() {
        let (alerts, state) = planner.plan(states: [withBalance(.openai, .usd(0))], thresholds: SpendThresholds(),
                                           state: .init(), now: testNow)
        #expect(alerts.isEmpty)
        #expect(state.fired.isEmpty)
    }
}
