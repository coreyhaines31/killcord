import Foundation
@testable import KillCordCore
import Testing

@Suite struct MoneyTests {
    @Test func parsesDecimalStringsExactly() {
        #expect(Money("12.345678")?.amount == decimal("12.345678"))
        #expect(Money("-0.5")?.amount == decimal("-0.5"))
        #expect(Money("1e2")?.amount == 100)
        #expect(Money("") == nil)
        #expect(Money("12,50") == nil)
        #expect(Money("$5") == nil)
        #expect(Money("NaN") == nil)
    }

    @Test func sumsWithoutFloatingPointDrift() {
        var total = Money.zero()
        for _ in 0..<10 { total = total + usd("0.1") }
        #expect(total.amount == 1)
        #expect(usd("0.1") + usd("0.2") == usd("0.3"))
    }

    @Test func minorUnitsAreCents() {
        #expect(Money.fromMinorUnits("123.45") == usd("1.2345"))
        #expect(Money.fromMinorUnits("41280.000000") == usd("412.8"))
        #expect(Money.fromCents(10000) == usd("100"))
    }

    @Test func formatsLikeAnInvoice() {
        #expect(MoneyText.string(usd("1234.5")) == "$1,234.50")
        #expect(MoneyText.string(usd("0.005")) == "$0.01")
        #expect(MoneyText.string(usd("0.004")) == "$0.00")
        #expect(MoneyText.string(usd("1234567.891")) == "$1,234,567.89")
        #expect(MoneyText.string(usd("-3.2")) == "-$3.20")
        #expect(MoneyText.string(Money(decimal("12"), Currency("eur"))) == "EUR 12.00")
    }

    @Test func compactFormForTheMenuBar() {
        #expect(MoneyText.compact(usd("12.4")) == "$12.40")
        #expect(MoneyText.compact(usd("212.07")) == "$212")
        #expect(MoneyText.compact(usd("1234")) == "$1.2k")
        #expect(MoneyText.compact(usd("48210")) == "$48k")
    }

    @Test func totalsKeepCurrenciesApart() {
        let totals = MoneyTotals([usd("1"), Money(decimal("2"), Currency("EUR")), usd("3")])
        #expect(totals.amount(in: .usd) == usd("4"))
        #expect(totals.amounts.map(\.currency.code) == ["USD", "EUR"])
        #expect(MoneyText.string(totals) == "$4.00 + EUR 2.00")
        #expect(MoneyText.string(MoneyTotals()) == "$0.00")
    }

    @Test func currencyCodesAreNormalized() {
        #expect(Currency("usd") == .usd)
        #expect(Currency(" Usd ") == .usd)
    }

    @Test func decodesJSONNumbersAndStringsWithoutDouble() throws {
        struct Box: Decodable { let a: FlexibleDecimal; let b: FlexibleDecimal; let c: FlexibleDecimal }
        let box = try JSONDecoder().decode(Box.self, from: Data(#"{"a": 12.4731, "b": "0.1", "c": 0.0001}"#.utf8))
        #expect(box.a.value == decimal("12.4731"))
        #expect(box.b.value == decimal("0.1"))
        #expect(box.c.value == decimal("0.0001"))
        #expect(box.a.value + box.c.value == decimal("12.4732"))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Box.self, from: Data(#"{"a": "abc", "b": 1, "c": 1}"#.utf8))
        }
    }

    @Test func billingWindowsFollowTheProvidersClock() {
        let utc = BillingWindow(now: testNow, timeZone: TimeZone(identifier: "UTC")!)
        #expect(utc.dayKey == "2026-11-15")
        #expect(utc.monthKey == "2026-11")
        #expect(utc.dayStart == Date(timeIntervalSince1970: 1_794_700_800))
        #expect(utc.monthStart == Date(timeIntervalSince1970: 1_793_491_200))
        #expect(utc.dayEnd == Date(timeIntervalSince1970: 1_794_787_200))

        // 1:30a UTC on Nov 1 is still Oct 31 in Pacific time, Google's billing clock.
        let early = Date(timeIntervalSince1970: 1_793_491_200 + 5400)
        let pacific = BillingWindow(now: early, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(pacific.dayKey == "2026-10-31")
        #expect(pacific.monthKey == "2026-10")
    }
}
