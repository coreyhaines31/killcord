import Foundation
@testable import KillCordCore
import Testing

@Suite struct FreshnessTests {
    let launched = testNow.addingTimeInterval(-6 * 3600)

    func state(checkedMinutesAgo minutes: Double, provider: ProviderID = .anthropic) -> ProviderState {
        ProviderState(provider: provider, connectionID: .of(provider), snapshot: SpendSnapshot(
            provider: provider, today: usd("1"), month: usd("2"),
            fetchedAt: testNow.addingTimeInterval(-minutes * 60)
        ))
    }

    func context(lastWake: Date? = nil, asleep: Bool = false, online: Bool = true) -> FreshnessContext {
        FreshnessContext(now: testNow, launchedAt: launched, lastWake: lastWake, isAsleep: asleep, isOnline: online,
                         interval: 15 * 60)
    }

    @Test func recentReadingIsLive() {
        let freshness = Freshness.of(state(checkedMinutesAgo: 5), context: context())
        #expect(freshness == .live(checkedAt: testNow.addingTimeInterval(-300)))
        #expect(freshness.isLive)
    }

    @Test func neverCheckedSaysSo() {
        let unread = ProviderState(provider: .openai, connectionID: .of(.openai))
        #expect(Freshness.of(unread, context: context()) == .neverChecked)
    }

    @Test func aReadingFromBeforeSleepIsStaleUntilTheNextCheck() {
        let wake = testNow.addingTimeInterval(-60)
        let before = Freshness.of(state(checkedMinutesAgo: 9 * 60 - 1, provider: .openai),
                                  context: FreshnessContext(now: testNow, launchedAt: testNow.addingTimeInterval(-86400),
                                                            lastWake: wake, interval: 15 * 60))
        guard case .stale(_, .slept) = before else { Issue.record("Got \(before)"); return }
        // Even a reading only two minutes old, if the Mac slept since.
        let justBefore = Freshness.of(state(checkedMinutesAgo: 2), context: context(lastWake: wake))
        guard case .stale(_, .slept) = justBefore else { Issue.record("Got \(justBefore)"); return }
        // After a check following wake, live again.
        let after = Freshness.of(state(checkedMinutesAgo: 0.5), context: context(lastWake: wake))
        #expect(after.isLive)
    }

    @Test func whileAsleepNothingIsLive() {
        let freshness = Freshness.of(state(checkedMinutesAgo: 1), context: context(asleep: true))
        guard case .stale(_, .slept) = freshness else { Issue.record("Got \(freshness)"); return }
    }

    @Test func aReadingFromAnEarlierRunIsStale() {
        let freshness = Freshness.of(state(checkedMinutesAgo: 7 * 60), context: context())
        guard case .stale(_, .notRunning) = freshness else { Issue.record("Got \(freshness)"); return }
    }

    @Test func offlineIsStale() {
        let freshness = Freshness.of(state(checkedMinutesAgo: 1), context: context(online: false))
        guard case .stale(_, .offline) = freshness else { Issue.record("Got \(freshness)"); return }
    }

    @Test func aFailedCheckMakesTheLastReadingStale() {
        var failing = state(checkedMinutesAgo: 10)
        failing.record(.server(status: 500), at: testNow)
        let freshness = Freshness.of(failing, context: context())
        guard case .stale(_, .failed) = freshness else { Issue.record("Got \(freshness)"); return }
    }

    @Test func overdueAfterTwoMissedIntervals() {
        #expect(Freshness.of(state(checkedMinutesAgo: 30), context: context()).isLive)
        let late = Freshness.of(state(checkedMinutesAgo: 33), context: context())
        guard case .stale(_, .overdue) = late else { Issue.record("Got \(late)"); return }
        // Google's own minimum is an hour, so 90 minutes is still on schedule there.
        #expect(Freshness.of(state(checkedMinutesAgo: 90, provider: .google), context: context()).isLive)
    }

    @Test func textNeverImpliesLiveCoverageWhenStale() {
        let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
     }()
        let at = ISO8601.date("2026-11-15T11:42:00Z")!
        #expect(SpendText.freshness(.stale(checkedAt: at, reason: .slept), now: testNow, calendar: calendar)
            == "Last checked 11:42a, not live")
        #expect(SpendText.freshness(.live(checkedAt: at), now: testNow, calendar: calendar) == "Checked 11:42a")
        #expect(SpendText.staleReason(.stale(checkedAt: at, reason: .slept))?.contains("asleep") == true)
        #expect(SpendText.staleReason(.live(checkedAt: at)) == nil)
    }
}

@Suite struct RefreshSchedulerTests {
    var scheduler = RefreshScheduler(interval: 15 * 60)

    init() {
        scheduler.add(.of(.anthropic), provider: .anthropic, now: testNow)
        scheduler.add(.of(.google), provider: .google, now: testNow)
    }

    @Test mutating func newProvidersAreDueAtOnceAndOnlyOnce() {
        #expect(scheduler.takeDue(now: testNow) == [.of(.anthropic), .of(.google)])
        #expect(scheduler.takeDue(now: testNow).isEmpty)
    }

    @Test mutating func successWaitsTheIntervalOrTheProvidersMinimum() {
        _ = scheduler.takeDue(now: testNow)
        scheduler.succeeded(.of(.anthropic), now: testNow)
        scheduler.succeeded(.of(.google), now: testNow)
        #expect(scheduler.entries[.of(.anthropic)]?.nextDue == testNow.addingTimeInterval(15 * 60))
        // Google's export runs hours behind: no point asking more than hourly.
        #expect(scheduler.entries[.of(.google)]?.nextDue == testNow.addingTimeInterval(60 * 60))
        #expect(scheduler.nextDue == testNow.addingTimeInterval(15 * 60))
    }

    @Test mutating func transientFailuresBackOffExponentially() {
        var delays: [TimeInterval] = []
        var now = testNow
        for _ in 0..<8 {
            _ = scheduler.takeDue(now: now)
            scheduler.failed(.of(.anthropic), error: .network, now: now)
            let due = scheduler.entries[.of(.anthropic)]!.nextDue!
            delays.append(due.timeIntervalSince(now))
            now = due
        }
        #expect(delays == [60, 120, 240, 480, 960, 1920, 3600, 3600])
        scheduler.succeeded(.of(.anthropic), now: now)
        #expect(scheduler.entries[.of(.anthropic)]?.failures == 0)
    }

    @Test mutating func rateLimitsWaitAtLeastRetryAfter() {
        _ = scheduler.takeDue(now: testNow)
        scheduler.failed(.of(.anthropic), error: .rateLimited(retryAfter: 900), now: testNow)
        #expect(scheduler.entries[.of(.anthropic)]?.nextDue == testNow.addingTimeInterval(900))
        // Refresh pressed during the wait doesn't hammer a rate-limited provider.
        scheduler.refreshAll(now: testNow.addingTimeInterval(60))
        #expect(scheduler.entries[.of(.anthropic)]?.nextDue == testNow.addingTimeInterval(900))
    }

    @Test mutating func keyProblemsStopUntilSomethingChanges() {
        _ = scheduler.takeDue(now: testNow)
        scheduler.failed(.of(.anthropic), error: .invalidKey, now: testNow)
        #expect(scheduler.entries[.of(.anthropic)]?.suspended == true)
        #expect(scheduler.takeDue(now: testNow.addingTimeInterval(86400)) == [])
        scheduler.wake(now: testNow.addingTimeInterval(86400))
        #expect(scheduler.entries[.of(.anthropic)]?.suspended == true)
        // A new key resumes it.
        scheduler.add(.of(.anthropic), provider: .anthropic, now: testNow.addingTimeInterval(86400))
        #expect(scheduler.takeDue(now: testNow.addingTimeInterval(86400)).contains(.of(.anthropic)))
    }

    @Test mutating func refreshResumesSuspendedProviders() {
        _ = scheduler.takeDue(now: testNow)
        scheduler.failed(.of(.anthropic), error: .missingScope(hint: ""), now: testNow)
        scheduler.succeeded(.of(.google), now: testNow)
        scheduler.refreshAll(now: testNow.addingTimeInterval(10))
        #expect(scheduler.takeDue(now: testNow.addingTimeInterval(10)) == [.of(.anthropic), .of(.google)])
    }

    @Test mutating func asksNothingWhileAsleepAndEveryoneSoonAfterWake() {
        _ = scheduler.takeDue(now: testNow)
        scheduler.succeeded(.of(.anthropic), now: testNow)
        scheduler.succeeded(.of(.google), now: testNow)
        scheduler.sleep()
        let morning = testNow.addingTimeInterval(8 * 3600)
        #expect(scheduler.takeDue(now: morning).isEmpty)
        #expect(scheduler.nextDue == nil)
        scheduler.wake(now: morning)
        #expect(scheduler.takeDue(now: morning).isEmpty)
        #expect(scheduler.takeDue(now: morning.addingTimeInterval(10)) == [.of(.anthropic), .of(.google)])
    }

    @Test mutating func aRequestLostToSleepIsRetriedAfterWake() {
        _ = scheduler.takeDue(now: testNow)
        scheduler.sleep()
        scheduler.wake(now: testNow.addingTimeInterval(3600))
        #expect(scheduler.entries[.of(.anthropic)]?.inFlight == false)
        #expect(scheduler.takeDue(now: testNow.addingTimeInterval(3610)) == [.of(.anthropic), .of(.google)])
    }

    @Test mutating func shorteningTheIntervalPullsTheNextCheckIn() {
        _ = scheduler.takeDue(now: testNow)
        scheduler.interval = 60 * 60
        scheduler.succeeded(.of(.anthropic), now: testNow)
        scheduler.setInterval(5 * 60, now: testNow)
        #expect(scheduler.entries[.of(.anthropic)]?.nextDue == testNow.addingTimeInterval(5 * 60))
    }

    @Test mutating func removedProvidersAreForgotten() {
        scheduler.remove(.of(.google))
        #expect(scheduler.takeDue(now: testNow) == [.of(.anthropic)])
        scheduler.succeeded(.of(.google), now: testNow)
        #expect(scheduler.entries[.of(.google)] == nil)
    }
}
