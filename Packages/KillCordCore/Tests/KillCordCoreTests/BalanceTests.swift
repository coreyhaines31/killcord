import Foundation
@testable import KillCordCore
import Testing

func withBalance(_ provider: ProviderID, _ balance: Balance?, today: String? = nil, at: Date = testNow,
                 number: Int = 1) -> ProviderState {
    ProviderState(provider: provider, connectionID: .of(provider, number), snapshot: SpendSnapshot(
        provider: provider, today: today.map(usd), month: nil, balance: balance, fetchedAt: at
    ))
}

@Suite struct BalanceTextTests {
    @Test func moneyAndUnitsRead() {
        #expect(BalanceText.remaining(.usd(Decimal(string: "12.4")!)) == "$12.40 left")
        let credits = Balance(remaining: 8200, unit: .units("credits"), kind: .allowance, limit: 10000)
        #expect(BalanceText.remaining(credits) == "8,200 of 10,000 credits left")
        #expect(BalanceText.amount(Decimal(string: "1234567.5")!, .units("API units")) == "1,234,567.5 API units")
        #expect(BalanceText.number(Decimal(string: "0.25")!) == "0.25")
        #expect(BalanceText.number(-1500) == "-1,500")
    }

    @Test func detailsSayWhatTheBalanceIsAndLabelEstimates() {
        let reset = testNow.addingTimeInterval(10 * 86400)
        let credits = Balance(remaining: 8200, unit: .units("credits"), kind: .allowance, limit: 10000, used: 1800,
                              dollarsPerUnit: Decimal(string: "0.01"), resetsAt: reset)
        let lines = BalanceText.details(credits, now: testNow, calendar: utcCalendar)
        #expect(lines[0] == "1,800 credits used this period.")
        #expect(lines[1] == "About $82.00 at $0.01 a credit (estimate).")
        #expect(lines[2].hasPrefix("Resets "))
        let prepaid = BalanceText.details(.usd(40, limit: 100), now: testNow)
        #expect(prepaid == ["$100.00 deposited.", "Prepaid: it doesn't reset. Top it up on the provider's site."])
        #expect(BalanceText.rateText(Decimal(string: "0.0004")!) == "$0.0004")
    }

    @Test func onlyUnitsWithARateHaveADollarEstimate() {
        #expect(Balance.usd(5).estimatedDollars == nil)
        #expect(Balance(remaining: 5, unit: .units("credits")).estimatedDollars == nil)
        #expect(Balance(remaining: 500, unit: .units("credits"), dollarsPerUnit: Decimal(string: "0.02")).estimatedDollars
            == Money(10))
    }

    var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

@Suite struct BalanceTotalsTests {
    let context = FreshnessContext(now: testNow, launchedAt: testNow.addingTimeInterval(-3600), lastWake: nil,
                                   isAsleep: false, isOnline: true, interval: 15 * 60)

    @Test func aBalanceNeverAddsIntoSpendTotals() {
        let states = [withBalance(.openai, .usd(900), today: "4.00"), reading(.anthropic, today: "1.00", month: "2")]
        let summary = SpendSummary(states: states, context: context)
        #expect(summary.today.amount(in: .usd) == Money(5))
        #expect(summary.month.amount(in: .usd) == Money(2))
    }

    @Test func balanceCapabilitiesSayWhichPeriodsCount() {
        let none = SpendCapability.balance(spend: [])
        #expect(!none.countsToday && !none.countsMonth && !none.showsMoney && none.showsBalance)
        let today = SpendCapability.balance(spend: .today)
        #expect(today.countsToday && !today.countsMonth && today.showsMoney)
        #expect(SpendCapability.dollars.countsToday && SpendCapability.dollars.countsMonth)
        #expect(!SpendCapability.dollars.showsBalance)
    }

    @Test func theSidebarLineLeadsWithTheBalance() {
        let state = withBalance(.openai, Balance(remaining: 8200, unit: .units("credits")), today: "4.00")
        let status = ProviderStatus.of(.openai, isConnected: true, state: state, freshness: .live(checkedAt: testNow),
                                       now: testNow)
        #expect(status.line == "Connected · 8,200 credits left")
    }
}

@Suite struct BalanceStorageTests {
    @Test func oldCachesAndLimitsWithoutBalancesStillDecode() throws {
        let snapshot = try JSONDecoder().decode(SpendSnapshot.self, from: Data("""
        {"provider":"openai","monthKind":{"calendarMonth":{}},"usage":[],"isEstimate":false,"fetchedAt":0}
        """.utf8))
        #expect(snapshot.balance == nil)
        let limits = try JSONDecoder().decode(SpendThresholds.Limits.self, from: Data(#"{"daily":5}"#.utf8))
        #expect(limits == .init(daily: 5))
    }

    @Test func aBalanceRoundTripsAndSyncsAsPlainStrings() throws {
        let balance = Balance(remaining: Decimal(string: "8200.5")!, unit: .units("credits"), kind: .allowance,
                              limit: 10000, dollarsPerUnit: Decimal(string: "0.01"), resetsAt: testNow)
        let snapshot = SpendSnapshot(provider: .openai, today: nil, month: nil, balance: balance, fetchedAt: testNow)
        let again = try JSONDecoder().decode(SpendSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(again == snapshot)
        let reading = try #require(SpendReading(snapshot, connectionID: .of(.openai)).balance)
        #expect(reading.remaining == "8200.5")
        #expect(reading.units == "credits")
        #expect(reading.currency == nil)
        #expect(reading.kind == "allowance")
        #expect(reading.dollarsPerUnit == "0.01")
    }
}
