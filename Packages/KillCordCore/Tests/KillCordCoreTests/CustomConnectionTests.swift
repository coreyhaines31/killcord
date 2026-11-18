import Foundation
@testable import KillCordCore
import Testing

func customCredentials(_ extra: [String: String] = [:]) -> ProviderCredentials {
    var values = FakeKeys.credentials(.custom).allValuesForTests
    for (key, value) in extra { values[key] = value }
    return ProviderCredentials(provider: .custom, values: values)
}

extension ProviderCredentials {
    var allValuesForTests: [String: String] {
        Dictionary(uniqueKeysWithValues: provider.info.fields.compactMap { field in self[field.id].map { (field.id, $0) } })
    }
}

@Suite struct JSONPathTests {
    let root: Any = (try? JSONSerialization.jsonObject(with: Data(#"""
    {"data":{"balance":"41.25","items":[{"credits":120},{"credits":7}],"ok":true,"none":null,
     "reset":"2026-12-01","epoch":1796083200,"ms":1796083200000}}
    """#.utf8))) ?? [:]

    @Test func followsKeysAndIndexes() {
        #expect(JSONPath("data.balance")?.decimal(in: root) == Decimal(string: "41.25"))
        #expect(JSONPath("$.data.items[1].credits")?.decimal(in: root) == 7)
        #expect(JSONPath("data.items.0.credits")?.decimal(in: root) == 120)
        #expect(JSONPath("data.items.5.credits")?.decimal(in: root) == nil)
        #expect(JSONPath("data.ok")?.decimal(in: root) == nil)
        #expect(JSONPath("data.none")?.value(in: root) == nil)
    }

    @Test func refusesMalformedPaths() {
        #expect(JSONPath("") == nil)
        #expect(JSONPath("data..balance") == nil)
        #expect(JSONPath("$") == nil)
    }

    @Test func readsDatesInThreeShapes() {
        let expected = ISO8601.date("2026-12-01T00:00:00Z")
        #expect(JSONPath("data.reset")?.date(in: root) == expected)
        #expect(JSONPath("data.epoch")?.date(in: root) == expected)
        #expect(JSONPath("data.ms")?.date(in: root) == expected)
    }
}

@Suite struct HostSafetyTests {
    @Test(arguments: ["127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254",
                      "100.64.0.1", "0.0.0.0", "224.0.0.1", "255.255.255.255", "::1", "::", "fc00::1", "fd12::1",
                      "fe80::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1", "2001:db8::1", "not-an-ip"])
    func privateAndOddAddressesAreNotPublic(_ address: String) {
        #expect(!HostSafety.isPublic(address))
    }

    @Test(arguments: ["93.184.215.14", "8.8.8.8", "172.32.0.1", "2606:4700:4700::1111", "::ffff:8.8.8.8"])
    func publicAddressesArePublic(_ address: String) {
        #expect(HostSafety.isPublic(address))
    }

    @Test func refusesLocalNamesLiteralsAndNamesThatResolveInside() {
        #expect(HostSafety.problem(host: "localhost", addresses: ["127.0.0.1"]) != nil)
        #expect(HostSafety.problem(host: "printer.local", addresses: nil) != nil)
        #expect(HostSafety.problem(host: "nas", addresses: nil) != nil)
        #expect(HostSafety.problem(host: "192.168.0.10", addresses: nil) != nil)
        #expect(HostSafety.problem(host: "[::1]", addresses: nil) != nil)
        #expect(HostSafety.problem(host: "rebind.example.com", addresses: ["93.184.215.14", "10.0.0.5"]) != nil)
        #expect(HostSafety.problem(host: "api.example.com", addresses: ["93.184.215.14"]) == nil)
    }
}

@Suite struct CustomConfigTests {
    @Test func refusesWhatItCantSendSafely() {
        let cases: [[String: String]] = [
            ["url": "http://api.example.com/balance"],
            ["url": "https://user:pw@api.example.com/balance"],
            ["url": "not a url"],
            ["authName": "X Bad Header"],
            ["authValue": "Bearer {key}\r\nX-Evil: 1"],
            ["body": "{\"a\":1}"],
            ["method": "POST", "body": "{not json"],
            ["remainingPath": "", "usedPath": "data.used"],
            ["remainingPath": "a..b"],
            ["dollarsPerUnit": "lots"],
            ["authStyle": "Basic", "key": "user:name"]
        ]
        for extra in cases {
            var values = customCredentials().allValuesForTests
            for (key, value) in extra { values[key] = value }
            #expect(throws: SpendError.self, "\(extra)") {
                try CustomConfig(ProviderCredentials(provider: .custom, values: values))
            }
        }
    }

    @Test func buildsEachAuthStyle() throws {
        let header = try CustomConfig(customCredentials()).request()
        #expect(header.headers["Authorization"] == "Bearer \(FakeKeys.custom)")
        #expect(header.method == .get && header.body == nil)
        #expect(header.limits == CustomConfig.limits)

        let custom = try CustomConfig(customCredentials(["authName": "x-api-key", "authValue": "{key}"])).request()
        #expect(custom.headers["x-api-key"] == FakeKeys.custom)
        #expect(custom.headers["Authorization"] == nil)

        let query = try CustomConfig(customCredentials(["authStyle": "Query parameter", "authName": "access_key"]))
            .request()
        #expect(query.query("access_key") == [FakeKeys.custom])
        #expect(query.headers["Authorization"] == nil)

        let basic = try CustomConfig(customCredentials(["authStyle": "Basic", "key": "me", "key2": "pw-TEST"])).request()
        #expect(basic.headers["Authorization"] == "Basic " + Data("me:pw-TEST".utf8).base64EncodedString())

        let none = try CustomConfig(customCredentials(["authStyle": "None"])).request()
        #expect(none.headers["Authorization"] == nil)

        let post = try CustomConfig(customCredentials(["method": "POST", "body": #"{"token":"{key}"}"#])).request()
        #expect(post.method == .post)
        #expect(post.headers["Content-Type"] == "application/json")
        #expect(post.body == Data(#"{"token":"\#(FakeKeys.custom)"}"#.utf8))
    }

    @Test func pollsNoFasterThanAllowed() throws {
        #expect(try CustomConfig(customCredentials()).interval == 15 * 60)
        #expect(try CustomConfig(customCredentials(["pollMinutes": "1"])).interval == 15 * 60)
        #expect(try CustomConfig(customCredentials(["pollMinutes": "240"])).interval == 240 * 60)
        #expect(try CustomConfig(customCredentials(["costsMoney": "Yes"])).interval == 60 * 60)
    }

    func balance(_ body: String, _ extra: [String: String] = [:]) throws -> Balance {
        try CustomConfig(customCredentials(extra)).balance(from: Data(body.utf8))
    }

    @Test func readsPathsPlainNumbersAndDerivedBalances() throws {
        #expect(try balance(#"{"data":{"balance":12.5}}"#) == .usd(Decimal(string: "12.5")!))
        #expect(try balance("  1234.5\n", ["remainingPath": ""]).remaining == Decimal(string: "1234.5"))
        let derived = try balance(#"{"u":250,"l":1000,"r":"2026-12-01"}"#,
                                  ["remainingPath": "", "usedPath": "u", "limitPath": "l", "resetPath": "r",
                                   "unit": "credits", "kind": "Allowance that resets", "dollarsPerUnit": "0.01"])
        #expect(derived == Balance(remaining: 750, unit: .units("credits"), kind: .allowance, limit: 1000, used: 250,
                                   dollarsPerUnit: Decimal(string: "0.01"), resetsAt: ISO8601.date("2026-12-01T00:00:00Z")))
    }

    @Test func scalesAndCurrencies() throws {
        #expect(try balance(#"{"data":{"balance":1250}}"#, ["scale": "Cents"]).remaining == Decimal(string: "12.5"))
        let micro = try balance(#"{"data":{"balance":18450000}}"#, ["scale": "Millionths"])
        #expect(micro.remaining == Decimal(string: "18.45"))
        let euro = try balance(#"{"data":{"balance":3,"cur":"eur"}}"#, ["currencyPath": "data.cur"])
        #expect(euro.unit == .money(Currency("EUR")))
        #expect(throws: SpendError.unexpectedResponse) {
            try balance(#"{"data":{"balance":3,"cur":"<b>"}}"#, ["currencyPath": "data.cur"])
        }
    }

    @Test func aMissingNumberIsAnUnexpectedResponse() {
        #expect(throws: SpendError.unexpectedResponse) { try balance(#"{"data":{}}"#) }
        #expect(throws: SpendError.unexpectedResponse) { try balance(#"{"data":{"balance":true}}"#) }
        #expect(throws: SpendError.unexpectedResponse) { try balance("<html>nope</html>", ["remainingPath": ""]) }
    }
}

@Suite struct CustomProviderTests {
    func client(_ json: String = #"{"data":{"balance":"9.75"}}"#, status: Int = 200) -> MockHTTPClient {
        MockHTTPClient { _ in HTTPResponse(status: status, json: json) }
    }

    @Test func readsTheBalanceFromTheAddressTyped() async throws {
        let http = client()
        let snapshot = try await CustomProvider(http: http).fetchSpend(customCredentials(), now: testNow)
        #expect(snapshot.balance == .usd(Decimal(string: "9.75")!))
        #expect(http.requests.map(\.url.absoluteString) == ["https://api.example.com/v1/balance"])
    }

    @Test func neverSendsToAPrivateAddress() async {
        let http = client()
        http.resolver = { _ in ["10.0.0.8"] }
        await #expect(throws: SpendError.self) {
            try await CustomProvider(http: http).fetchSpend(customCredentials(), now: testNow)
        }
        let literal = client()
        await #expect(throws: SpendError.self) {
            try await CustomProvider(http: literal).fetchSpend(customCredentials(["url": "https://127.0.0.1/b"]),
                                                               now: testNow)
        }
        #expect(http.requests.isEmpty && literal.requests.isEmpty)
    }

    @Test func aNameThatDoesntResolveSendsNothing() async {
        let http = client()
        http.resolver = { _ in nil }
        await #expect(throws: SpendError.network) {
            try await CustomProvider(http: http).fetchSpend(customCredentials(), now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func refusesAnOversizedReply() async {
        let big = #"{"data":{"balance":1},"pad":""# + String(repeating: "x", count: 300 * 1024) + #""}"#
        await #expect(throws: SpendError.unexpectedResponse) {
            try await CustomProvider(http: client(big)).fetchSpend(customCredentials(), now: testNow)
        }
    }

    @Test func errorsNeverCarryTheKeyWhereverItWasSent() async throws {
        let styles: [[String: String]] = [
            [:], ["authStyle": "Query parameter", "authName": "api_key"],
            ["authStyle": "Basic", "key": "basic-user-TEST", "key2": "basic-pass-TEST-0099"],
            ["method": "POST", "authStyle": "None", "body": #"{"token":"{key}"}"#]
        ]
        for style in styles {
            let credentials = customCredentials(style)
            let used = try CustomConfig(credentials).secrets.filter { !$0.hasPrefix("Bearer ") && !$0.contains("=") }
            let echoed = used.joined(separator: " ")
            let http = client(#"{"error":{"message":"bad key \#(echoed)"}}"#, status: 400)
            do {
                _ = try await CustomProvider(http: http).fetchSpend(credentials, now: testNow)
                Issue.record("accepted a 400")
            } catch let error as SpendError {
                let text = error.message(for: .custom) + String(describing: error)
                for secret in used {
                    #expect(!text.contains(secret), "\(style) leaked: \(text)")
                }
                #expect(text.contains("[redacted]"))
            }
        }
    }

    @Test func aRejectedKeyIsSaidPlainly() async {
        await #expect(throws: SpendError.invalidKey) {
            try await CustomProvider(http: client("{}", status: 401)).fetchSpend(customCredentials(), now: testNow)
        }
    }

    @Test func itsCopySaysKillCordCantVerifyTheNumbers() {
        let info = ProviderID.custom.info
        #expect(info.overview.contains("can't verify"))
        #expect(ProviderID.custom.keyPower == .canManage)
        for text in [info.overview, info.keyPowerWarning ?? "", info.lag.note] + info.fields.map(\.help)
            + info.setupSteps.flatMap({ [$0.title, $0.detail] }) {
            #expect(!text.contains("\u{2014}"))
        }
    }
}

@Suite struct CustomIntervalTests {
    @Test func theSchedulerKeepsAConnectionsOwnFloor() {
        var scheduler = RefreshScheduler(interval: 5 * 60)
        let id = UUID.of(.custom)
        scheduler.add(id, provider: .custom, now: testNow, floor: 3600)
        _ = scheduler.takeDue(now: testNow)
        scheduler.succeeded(id, now: testNow)
        #expect(scheduler.entries[id]?.nextDue == testNow.addingTimeInterval(3600))
    }

    @Test func freshnessUsesTheFloorBeforeCallingItOverdue() {
        var state = ProviderState(provider: .custom, connectionID: .of(.custom), snapshot: SpendSnapshot(
            provider: .custom, today: nil, month: nil, balance: .usd(1), fetchedAt: testNow))
        let context = FreshnessContext(now: testNow.addingTimeInterval(50 * 60),
                                       launchedAt: testNow.addingTimeInterval(-60), lastWake: nil, isAsleep: false,
                                       isOnline: true, interval: 5 * 60)
        #expect(!Freshness.of(state, context: context).isLive)
        state.refreshFloor = 3600
        #expect(Freshness.of(state, context: context).isLive)
    }
}

#if !canImport(FoundationNetworking)
@Suite struct SameHostRedirectTests {
    @Test func followsOnlyRedirectsThatStayOnTheSameHost() {
        let from = URL(string: "https://api.example.com/v1/balance")!
        #expect(SameHostRedirects.allows(from: from, to: URL(string: "https://API.example.com/v2/balance")!))
        #expect(!SameHostRedirects.allows(from: from, to: URL(string: "https://evil.example.net/v1/balance")!))
        #expect(!SameHostRedirects.allows(from: from, to: URL(string: "http://api.example.com/v1/balance")!))
        #expect(!SameHostRedirects.allows(from: from, to: URL(string: "https://api.example.com:8443/v1")!))
    }
}
#endif

@Suite struct CustomSetupLayoutTests {
    @Test func onlyTheEssentialsShowFirst() {
        let visible = ProviderID.custom.info.fields.filter { !$0.isAdvanced }.map(\.id)
        #expect(visible == ["serviceName", "url", "authStyle", "key", "remainingPath", "kind"])
        #expect(ProviderID.allCases.filter { $0 != .custom }.allSatisfy { $0.info.fields.allSatisfy { !$0.isAdvanced } })
    }

    @Test func namesTheFieldAtFault() {
        func problem(_ extra: [String: String]) -> String? {
            CustomConfig.fieldWithProblem(customCredentials(extra))
        }
        #expect(problem([:]) == nil)
        #expect(problem(["url": "http://api.example.com"]) == "url")
        #expect(problem(["authName": "Bad Header"]) == "authName")
        #expect(problem(["authStyle": "Query parameter", "key": ""]) == "key")
        #expect(problem(["authValue": "Bearer {key}\nX: 1"]) == "authValue")
        #expect(problem(["method": "POST", "body": "{nope"]) == "body")
        #expect(problem(["usedPath": "a..b"]) == "usedPath")
        #expect(problem(["remainingPath": "", "usedPath": "data.used"]) == "limitPath")
        #expect(problem(["dollarsPerUnit": "lots"]) == "dollarsPerUnit")
    }
}
