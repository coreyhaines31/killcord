// Fixtures follow Vapi's documented analytics schema: https://docs.vapi.ai/api-reference/analytics/get
import Foundation
@testable import KillCordCore
import Testing

@Suite struct VapiProviderTests {
    static let answer = #"[{"name":"killcord-spend","timeRange":{"step":"day"},"result":["#
        + #"{"date":"2026-11-03T00:00:00.000Z","cost":3.5},{"date":"2026-11-15T00:00:00.000Z","cost":1.25}]}]"#

    @Test func sumsCallCostsByDayWithOneQuery() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 201, json: Self.answer) }
        let snapshot = try await VapiProvider(http: http).fetchSpend(FakeKeys.credentials(.vapi), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://api.vapi.ai/analytics")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.vapi)")
        let body = try #require(request.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let query = try #require((body["queries"] as? [[String: Any]])?.first)
        #expect(query["table"] as? String == "call")
        let operation = try #require((query["operations"] as? [[String: String]])?.first)
        #expect(operation == ["operation": "sum", "column": "cost", "alias": "cost"])
        let range = try #require(query["timeRange"] as? [String: String])
        #expect(range == ["step": "day", "start": "2026-11-01T00:00:00Z", "end": "2026-11-15T18:30:00Z",
                          "timezone": "UTC"])
        #expect(snapshot.month == usd("4.75"))
        #expect(snapshot.today == usd("1.25"))
    }

    @Test func noCallsIsZero() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"[{"name":"killcord-spend","result":[]}]"#) }
        let snapshot = try await VapiProvider(http: http).fetchSpend(FakeKeys.credentials(.vapi), now: testNow)
        #expect(snapshot.month == usd("0"))
        #expect(snapshot.today == usd("0"))
    }

    @Test func anAnswerToAnotherQueryIsUnexpected() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"[{"name":"other","result":[]}]"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await VapiProvider(http: http).fetchSpend(FakeKeys.credentials(.vapi), now: testNow)
        }
    }

    @Test func aRejectedKeyIsInvalid() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 401, json: #"{"message":"Invalid Key"}"#) }
        await #expect(throws: SpendError.invalidKey) {
            try await VapiProvider(http: http).fetchSpend(FakeKeys.credentials(.vapi), now: testNow)
        }
    }
}
