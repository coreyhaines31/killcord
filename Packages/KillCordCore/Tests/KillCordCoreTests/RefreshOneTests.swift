import Foundation
@testable import KillCordCore
import Testing

@Suite struct RefreshOneTests {
    @Test func refreshOneProviderUnsuspendsOnlyIt() {
        var scheduler = RefreshScheduler()
        scheduler.add(.of(.anthropic), provider: .anthropic, now: testNow)
        scheduler.add(.of(.openai), provider: .openai, now: testNow)
        _ = scheduler.takeDue(now: testNow)
        scheduler.failed(.of(.anthropic), error: .invalidKey, now: testNow)
        scheduler.failed(.of(.openai), error: .invalidKey, now: testNow)
        scheduler.refresh(.of(.anthropic), now: testNow)
        #expect(scheduler.takeDue(now: testNow) == [.of(.anthropic)])
    }
}
