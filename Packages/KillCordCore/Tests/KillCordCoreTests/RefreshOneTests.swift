import Foundation
@testable import KillCordCore
import Testing

@Suite struct RefreshOneTests {
    @Test func refreshOneProviderUnsuspendsOnlyIt() {
        var scheduler = RefreshScheduler()
        scheduler.add(.anthropic, now: testNow)
        scheduler.add(.openai, now: testNow)
        _ = scheduler.takeDue(now: testNow)
        scheduler.failed(.anthropic, error: .invalidKey, now: testNow)
        scheduler.failed(.openai, error: .invalidKey, now: testNow)
        scheduler.refresh(.anthropic, now: testNow)
        #expect(scheduler.takeDue(now: testNow) == [.anthropic])
    }
}
