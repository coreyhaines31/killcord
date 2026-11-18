import Foundation
@testable import KillCordCore
import Testing

@Suite struct SpendReadingTests {
    func encode(_ readings: [SpendReading]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try #require(String(data: try encoder.encode(readings), encoding: .utf8))
    }

    @Test func readingsCarryAmountsAsTextAndTheConnectionID() throws {
        let registry = oneEach([.anthropic, .cloudflare, .neon])
        let start = testNow.addingTimeInterval(-10 * 86400)
        let states = [
            ProviderState(provider: .cloudflare, connectionID: .of(.cloudflare), snapshot: SpendSnapshot(
                provider: .cloudflare, today: nil, month: usd("41.07"), monthKind: .billingPeriod(start: start),
                fetchedAt: testNow)),
            ProviderState(provider: .anthropic, connectionID: .of(.anthropic), snapshot: SpendSnapshot(
                provider: .anthropic, today: usd("18.42"), month: usd("212.5"), isEstimate: true,
                fetchedAt: testNow)),
            ProviderState(provider: .neon, connectionID: .of(.neon), snapshot: SpendSnapshot(
                provider: .neon, today: nil, month: nil,
                usage: [UsageMetric(id: "compute", name: "Compute", value: decimal("12.75"), unit: "CU-hours")],
                fetchedAt: testNow)),
            // Never read yet, and one with no record: both left out.
            ProviderState(provider: .openai, connectionID: .of(.openai)),
            ProviderState(provider: .vercel, connectionID: .of(.vercel), snapshot: SpendSnapshot(
                provider: .vercel, today: usd("1"), month: usd("2"), fetchedAt: testNow))
        ]
        let readings = SpendReading.all(states: states, registry: registry)
        #expect(readings.map(\.provider) == [.anthropic, .cloudflare, .neon])
        #expect(readings[0].connectionID == UUID.of(.anthropic))
        #expect(readings[0].today == .init(amount: "18.42", currency: "USD"))
        #expect(readings[0].isEstimate)
        #expect(readings[1].monthKind == "billingPeriod")
        #expect(readings[1].periodStart == start)
        #expect(readings[2].usage == [.init(id: "compute", name: "Compute", value: "12.75", unit: "CU-hours")])
        let text = try encode(readings)
        #expect(!text.contains(FakeKeys.anthropic))
        #expect(text.contains("\"2026-11-15T18:30:00Z\""))
        #expect(text.contains("\"amount\":\"212.5\""))
    }

    @Test func twoAccountsOfOneProviderStayApart() {
        var registry = oneEach([.anthropic])
        let second = registry.add(.anthropic, now: testNow.addingTimeInterval(60))
        let states = [
            ProviderState(provider: .anthropic, connectionID: second.id, snapshot: SpendSnapshot(
                provider: .anthropic, today: usd("2"), month: usd("20"), fetchedAt: testNow)),
            ProviderState(provider: .anthropic, connectionID: .of(.anthropic), snapshot: SpendSnapshot(
                provider: .anthropic, today: usd("1"), month: usd("10"), fetchedAt: testNow))
        ]
        let readings = SpendReading.all(states: states, registry: registry)
        #expect(readings.map(\.connectionID) == [.of(.anthropic), second.id])
        #expect(readings.map(\.today?.amount) == ["1", "2"])
    }
}
