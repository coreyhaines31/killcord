// swiftlint:disable line_length
// Inline JSON fixtures preserve the exact provider response shape.
import Foundation
@testable import KillCordCore
import Testing

@Suite struct AnthropicProviderTests {
    func client() throws -> MockHTTPClient {
        let page1 = try json("anthropic-cost-report-page1.json")
        let page2 = try json("anthropic-cost-report-page2.json")
        return MockHTTPClient { request in
            request.query("page").first == "page_2_token" ? page2 : page1
        }
    }

    @Test func buildsTheCostReportRequest() async throws {
        let http = try client()
        _ = try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: testNow)
        let first = try #require(http.requests.first)
        #expect(first.method == .get)
        #expect(first.url.host == "api.anthropic.com")
        #expect(first.path == "/v1/organizations/cost_report")
        #expect(first.headers["x-api-key"] == FakeKeys.anthropic)
        #expect(first.headers["anthropic-version"] == "2023-06-01")
        #expect(first.query("starting_at") == ["2026-11-01T00:00:00Z"])
        // The API clamps ending_at to the start of today, so sending one can make the range empty (HTTP 400).
        #expect(first.query("ending_at").isEmpty)
        #expect(first.query("bucket_width") == ["1d"])
        #expect(first.query("limit") == ["31"])
        #expect(first.query("page").isEmpty)
        // The key goes only in the header, never the URL.
        #expect(!first.url.absoluteString.contains(FakeKeys.anthropic))
    }

    @Test func followsPagesAndConvertsCentsToDollars() async throws {
        let http = try client()
        let snapshot = try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: testNow)
        #expect(http.requests.count == 2)
        #expect(http.requests[1].query("page") == ["page_2_token"])
        // 1834.52 + 100.005 + 0.995 + 250 + 1234.5 + 0.5 cents.
        #expect(snapshot.month == usd("34.2052"))
        // Only the Nov 15 bucket: 1234.5 + 0.5 cents.
        #expect(snapshot.today == usd("12.35"))
        #expect(snapshot.monthKind == .calendarMonth)
        #expect(!snapshot.isEstimate)
    }

    @Test func emptyMonthIsZeroNotMissing() async throws {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"data":[{"starting_at":"2026-11-15T00:00:00Z","ending_at":"2026-11-16T00:00:00Z","results":[]}],"has_more":false,"next_page":null}"#)
        }
        let snapshot = try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: testNow)
        #expect(snapshot.today == .zero())
        #expect(snapshot.month == .zero())
    }

    @Test func firstOfTheMonthStartsYesterdayButCountsOnlyThisMonth() async throws {
        let firstOfMonth = ISO8601.date("2026-11-01T10:00:00Z")!
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"data":[{"starting_at":"2026-10-31T00:00:00Z","ending_at":"2026-11-01T00:00:00Z","results":[{"amount":"5000","currency":"USD","workspace_id":null,"model":null}]},{"starting_at":"2026-11-01T00:00:00Z","ending_at":"2026-11-02T00:00:00Z","results":[{"amount":"125","currency":"USD","workspace_id":null,"model":null}]}],"has_more":false,"next_page":null}"#)
        }
        let snapshot = try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: firstOfMonth)
        #expect(http.requests.first?.query("starting_at") == ["2026-10-31T00:00:00Z"])
        #expect(http.requests.first?.query("ending_at").isEmpty == true)
        // October's $50 is outside this month.
        #expect(snapshot.month == usd("1.25"))
        #expect(snapshot.today == usd("1.25"))
    }

    @Test func firstOfTheMonthWithoutTodaysBucketIsZeroMonthAndUnreportedToday() async throws {
        let firstOfMonth = ISO8601.date("2026-11-01T10:00:00Z")!
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"data":[{"starting_at":"2026-10-31T00:00:00Z","ending_at":"2026-11-01T00:00:00Z","results":[{"amount":"5000","currency":"USD"}]}],"has_more":false,"next_page":null}"#)
        }
        let snapshot = try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: firstOfMonth)
        #expect(snapshot.month == .zero())
        #expect(snapshot.today == nil)
    }

    @Test func todaysBucketAbsentLeavesTodayUnreported() async throws {
        // The response stops at the start of today, as the live API was seen to do.
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"data":[{"starting_at":"2026-11-01T00:00:00Z","ending_at":"2026-11-02T00:00:00Z","results":[{"amount":"1000","currency":"USD","workspace_id":null,"model":null}]},{"starting_at":"2026-11-14T00:00:00Z","ending_at":"2026-11-15T00:00:00Z","results":[{"amount":"250","currency":"USD","workspace_id":null,"model":null}]}],"has_more":false,"next_page":null}"#)
        }
        let snapshot = try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: testNow)
        #expect(snapshot.month == usd("12.50"))
        #expect(snapshot.today == nil)
    }

    @Test func mapsHTTPFailures() async throws {
        for (status, expected) in [(401, SpendError.invalidKey), (500, .server(status: 500)), (418, .unexpectedStatus(418))] {
            let http = MockHTTPClient { _ in HTTPResponse(status: status, json: #"{"error":{}}"#) }
            await #expect(throws: expected) {
                try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: testNow)
            }
        }
        let limited = MockHTTPClient { _ in HTTPResponse(status: 429, json: "{}", headers: ["Retry-After": "30"]) }
        await #expect(throws: SpendError.rateLimited(retryAfter: 30)) {
            try await AnthropicProvider(http: limited).validate(FakeKeys.credentials(.anthropic), now: testNow)
        }
        let forbidden = MockHTTPClient { _ in HTTPResponse(status: 403, json: "{}") }
        do {
            try await AnthropicProvider(http: forbidden).validate(FakeKeys.credentials(.anthropic), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            guard case .missingScope = error else { Issue.record("Got \(error)"); return }
        }
    }

    @Test func rejectsAnUnexpectedShape() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"data":[{"starting_at":"x","ending_at":"y","results":[{"amount":"abc"}]}],"has_more":false}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await AnthropicProvider(http: http).fetchSpend(FakeKeys.credentials(.anthropic), now: testNow)
        }
    }

    @Test func requiresAKey() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        await #expect(throws: SpendError.notConfigured) {
            try await AnthropicProvider(http: http).fetchSpend(ProviderCredentials(provider: .anthropic, values: [:]),
                                                               now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func validatesFromYesterdaySoTheRangeIsNeverEmpty() async throws {
        let http = try client()
        try await AnthropicProvider(http: http).validate(FakeKeys.credentials(.anthropic), now: testNow)
        #expect(http.requests.first?.query("starting_at") == ["2026-11-14T00:00:00Z"])
        #expect(http.requests.first?.query("ending_at").isEmpty == true)
        #expect(http.requests.first?.query("limit") == ["1"])
    }
}

@Suite struct OpenAIProviderTests {
    @Test func buildsTheCostsRequest() async throws {
        let http = MockHTTPClient(routes: ["/organization/costs": try json("openai-costs.json")])
        _ = try await OpenAIProvider(http: http).fetchSpend(FakeKeys.credentials(.openai), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.url.host == "api.openai.com")
        #expect(request.path == "/v1/organization/costs")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.openai)")
        #expect(request.query("start_time") == ["1793491200"])
        #expect(request.query("end_time") == ["1794787200"])
        #expect(request.query("bucket_width") == ["1d"])
        #expect(request.query("limit") == ["31"])
    }

    @Test func sumsDollarAmountsExactly() async throws {
        let http = MockHTTPClient(routes: ["/organization/costs": try json("openai-costs.json")])
        let snapshot = try await OpenAIProvider(http: http).fetchSpend(FakeKeys.credentials(.openai), now: testNow)
        #expect(snapshot.month == usd("13.8332"))
        #expect(snapshot.today == usd("1.0601"))
    }

    @Test func followsPages() async throws {
        let first = HTTPResponse(status: 200, json: #"{"object":"page","data":[{"object":"bucket","start_time":1793491200,"end_time":1793577600,"results":[{"object":"organization.costs.result","amount":{"value":1.5,"currency":"usd"}}]}],"has_more":true,"next_page":"page_AAA"}"#)
        let second = HTTPResponse(status: 200, json: #"{"object":"page","data":[{"object":"bucket","start_time":1794700800,"end_time":1794787200,"results":[{"object":"organization.costs.result","amount":{"value":2.25,"currency":"usd"}}]}],"has_more":false,"next_page":null}"#)
        let http = MockHTTPClient { $0.query("page") == ["page_AAA"] ? second : first }
        let snapshot = try await OpenAIProvider(http: http).fetchSpend(FakeKeys.credentials(.openai), now: testNow)
        #expect(http.requests.count == 2)
        #expect(snapshot.month == usd("3.75"))
        #expect(snapshot.today == usd("2.25"))
    }

    @Test func verifiesTheHardLimit() async throws {
        let http = MockHTTPClient(routes: ["/organization/spend_limit": try json("openai-spend-limit.json")])
        let results = await OpenAIProvider(http: http).verifyCaps(FakeKeys.credentials(.openai), now: testNow)
        #expect(results == [CapVerification(capID: OpenAIProvider.hardLimitCapID,
                                            status: .on("OpenAI reports a hard limit of $100.00 a month."),
                                            checkedAt: testNow)])
        #expect(http.requests.first?.path == "/v1/organization/spend_limit")
    }

    @Test func reportsAMissingHardLimit() async throws {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"object":"organization.spend_limit","threshold_amount":0,"currency":"USD","interval":"month","enforcement":{"status":"inactive"}}"#)
        }
        let results = await OpenAIProvider(http: http).verifyCaps(FakeKeys.credentials(.openai), now: testNow)
        guard case .off = results.first?.status else { Issue.record("Expected off, got \(results)"); return }
    }

    @Test func verificationFailureIsSilent() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: "{}") }
        #expect(await OpenAIProvider(http: http).verifyCaps(FakeKeys.credentials(.openai), now: testNow).isEmpty)
    }
}

// swiftlint:enable line_length
