import Foundation
@testable import KillCordCore
import Testing

/// A small deterministic generator (SplitMix64), so property runs are repeatable.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@Suite struct AttributionTests {
    /// A provider amount the way Anthropic sends it: cents with six decimals, from an integer count of
    /// millionths of a cent. The oracle sums the integers, so it never touches Decimal.
    static func minorString(_ microCents: Int) -> String {
        let sign = microCents < 0 ? "-" : ""
        let magnitude = abs(microCents)
        return "\(sign)\(magnitude / 1_000_000).\(String(format: "%06d", magnitude % 1_000_000))"
    }

    static func dollars(microCents: Int) -> Decimal {
        Decimal(microCents) / Decimal(100_000_000)
    }

    @Test func reconciliationHoldsForGeneratedReports() throws {
        var random = SeededRandom(seed: 0x6B69_6C6C_636F_7264)
        let units = (0..<12).map { AttributionUnitRef(kind: .apiKey, externalID: "apikey_\($0)") }
        let day: TimeInterval = 86_400
        for _ in 0..<500 {
            let rowCount = Int.random(in: 0...60, using: &random)
            var rows: [AttributedSpend] = []
            var oracleTotal = 0
            var oracleUnassigned = 0
            var oracleByUnit: [AttributionUnitRef: Int] = [:]
            for _ in 0..<rowCount {
                // Up to $50,000 per row, down to a millionth of a cent; some rows are credits (negative).
                let micro = Int.random(in: -2_000_000...5_000_000_000_000, using: &random)
                let unit = Bool.random(using: &random) && Int.random(in: 0...4, using: &random) == 0
                    ? nil : units.randomElement(using: &random)
                let dayIndex = Double(Int.random(in: 0..<31, using: &random))
                let bucket = Date(timeIntervalSince1970: 1_790_000_000 + dayIndex * day)
                let money = try #require(Money.fromMinorUnits(Self.minorString(micro)))
                rows.append(AttributedSpend(bucketStart: bucket, bucketEnd: bucket.addingTimeInterval(day),
                                            unit: unit, amount: money))
                oracleTotal += micro
                if let unit { oracleByUnit[unit, default: 0] += micro } else { oracleUnassigned += micro }
            }
            let report = AttributionReport(
                provider: .anthropic, dimension: .apiKey, rangeStart: testNow, rangeEnd: testNow,
                rows: rows.shuffled(using: &random),
                providerTotal: MoneyTotals([Money(Self.dollars(microCents: oracleTotal))]),
                dataRefreshedAt: nil, meaningVerified: true)

            #expect(report.reconciles, "gap \(report.gap.amounts)")
            #expect((report.unassigned.amount(in: .usd)?.amount ?? 0) == Self.dollars(microCents: oracleUnassigned))
            for (unit, micro) in oracleByUnit {
                #expect(report.byUnit[unit]?.amount(in: .usd)?.amount == Self.dollars(microCents: micro))
            }

            // One millionth of a cent off is caught, and the gap is exactly that amount.
            var off = report
            off.providerTotal = MoneyTotals([Money(Self.dollars(microCents: oracleTotal + 1))])
            #expect(!off.reconciles)
            #expect(off.gap.amount(in: .usd)?.amount == Self.dollars(microCents: 1))
        }
    }

    @Test func currenciesNeverMix() {
        let day = DateInterval(start: testNow, duration: 86_400)
        let report = AttributionReport(
            provider: .openai, dimension: .project, rangeStart: day.start, rangeEnd: day.end,
            rows: [AttributedSpend(bucketStart: day.start, bucketEnd: day.end, unit: nil,
                                   amount: Money(5, Currency("EUR")))],
            providerTotal: MoneyTotals([Money(5)]), dataRefreshedAt: nil, meaningVerified: true)
        // 5 USD expected, 5 EUR found: not the same thing.
        #expect(!report.reconciles)
        #expect(Set(report.gap.amounts) == [Money(5), Money(-5, Currency("EUR"))])
    }

    @Test func windowsCoverTheRangeExactly() {
        let start = ISO8601.date("2026-01-01T00:00:00Z")!
        let end = ISO8601.date("2026-11-15T00:00:00Z")!
        let windows = AttributionWindows.split(start: start, end: end, maxDays: 31)
        #expect(windows.first?.start == start)
        #expect(windows.last?.end == end)
        #expect(windows.allSatisfy { $0.duration <= 31 * 86_400 })
        for (lhs, rhs) in zip(windows, windows.dropFirst()) { #expect(lhs.end == rhs.start) }
        #expect(AttributionWindows.split(start: end, end: start, maxDays: 31).isEmpty)
    }

    @Test func keyHintsKeepOnlyTheLastFourCharacters() {
        #expect(AttributionUnit.keyHint(fromRedacted: "sk-ant-api03-R2D...igAA") == "Ending in igAA")
        #expect(AttributionUnit.keyHint(fromRedacted: "sk-proj-abc****wxyz") == "Ending in wxyz")
        #expect(AttributionUnit.keyHint(fromRedacted: "sk-...ab") == nil)
        #expect(AttributionUnit.keyHint(fromRedacted: nil) == nil)
    }

    @Test func roundTripsAsJSON() throws {
        let unit = AttributionUnit(provider: .anthropic, kind: .apiKey, externalID: "apikey_1", label: "CI",
                                   keyHint: "Ending in igAA", ownerEmail: "dev@example.test", parentID: "wrkspc_1")
        let decoded = try JSONDecoder().decode(AttributionUnit.self, from: JSONEncoder().encode(unit))
        #expect(decoded == unit)
        let json = try #require(String(bytes: try JSONEncoder().encode(unit.ref), encoding: .utf8))
        #expect(json.contains(#""kind":"api_key""#))
    }
}
