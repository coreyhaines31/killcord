import Foundation
@testable import KillCordCore
import Testing

@Suite struct ProviderStatusTests {
    func status(_ provider: ProviderID = .anthropic, connected: Bool = true, state: ProviderState?,
                freshness: Freshness, checking: Bool = false) -> ProviderStatus {
        ProviderStatus.of(provider, isConnected: connected, state: state, freshness: freshness,
                          isChecking: checking, now: testNow)
    }

    @Test func liveDollarsShowTodayFirst() {
        let state = reading(.anthropic, today: "18.42", month: "212.07")
        let result = status(state: state, freshness: .live(checkedAt: testNow))
        #expect(result == ProviderStatus(light: .go, label: "Connected", line: "Connected · $18.42 today"))
    }

    @Test func fallsBackToTheMonthThenUsage() {
        let vercel = reading(.vercel, today: nil, month: "24")
        #expect(status(.vercel, state: vercel, freshness: .live(checkedAt: testNow)).line
            == "Connected · $24.00 this month")
        let neon = ProviderState(provider: .neon, connectionID: .of(.neon), snapshot: SpendSnapshot(
            provider: .neon, today: nil, month: nil,
            usage: [UsageMetric(id: "c", name: "Compute", value: decimal("41.7"), unit: "CU-hours")],
            fetchedAt: testNow))
        #expect(status(.neon, state: neon, freshness: .live(checkedAt: testNow)).line
            == "Connected · 41.7 CU-hours")
    }

    @Test func staleSaysHowLongAgo() {
        let checked = testNow.addingTimeInterval(-3 * 3600 - 300)
        let result = status(state: reading(.anthropic, today: "1", month: "2", at: checked),
                            freshness: .stale(checkedAt: checked, reason: .slept))
        #expect(result == ProviderStatus(light: .caution, label: "Not live", line: "Checked 3h ago, not live"))
    }

    @Test func errorsAPersonMustFixAreStop() {
        let rejected = ProviderState(provider: .twilio, connectionID: .of(.twilio), lastAttempt: testNow,
                                     lastError: .invalidKey)
        #expect(status(.twilio, state: rejected, freshness: .neverChecked)
            == ProviderStatus(light: .stop, label: "Key rejected", line: "Key rejected"))
        let scope = ProviderState(provider: .openai, connectionID: .of(.openai), lastAttempt: testNow,
                                  lastError: .missingScope(hint: "x"))
        #expect(status(.openai, state: scope, freshness: .neverChecked).line == "No billing access")
    }

    @Test func notConnectedCapsOnlyAndChecking() {
        #expect(status(connected: false, state: nil, freshness: .neverChecked)
            == ProviderStatus(light: .off, label: "Not connected", line: "Not connected"))
        #expect(status(.supabase, connected: false, state: nil, freshness: .neverChecked).line == "Caps only")
        let unread = ProviderState(provider: .anthropic, connectionID: .of(.anthropic))
        #expect(status(state: unread, freshness: .neverChecked, checking: true).light == .caution)
        #expect(status(state: unread, freshness: .neverChecked).line == "Connected, not read yet")
    }

    @Test func agoIsCoarse() {
        #expect(SpendText.ago(testNow.addingTimeInterval(-20), now: testNow) == "just now")
        #expect(SpendText.ago(testNow.addingTimeInterval(-720), now: testNow) == "12m ago")
        #expect(SpendText.ago(testNow.addingTimeInterval(-3 * 86400), now: testNow) == "3d ago")
    }
}

@Suite struct CapLightTests {
    @Test func checklistLights() {
        #expect(CapAuditState.Status.notDone.light == .off)
        #expect(CapAuditState.Status.markedDone(at: testNow, recheck: false).light == .go)
        #expect(CapAuditState.Status.markedDone(at: testNow, recheck: true).label == "Check again")
        #expect(CapAuditState.Status.verifiedOff("x", at: testNow).light == .caution)
        #expect(CapAuditState.Status.enforced("x", at: testNow).light == .stop)
    }
}
