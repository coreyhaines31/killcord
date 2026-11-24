// Fixtures follow Retell's documented schema: https://docs.retellai.com/api-references/list-calls
import Foundation
@testable import KillCordCore
import Testing

@Suite struct RetellProviderTests {
    /// Nov 15 2026, 09:00 UTC and Nov 3 2026, 12:00 UTC, in epoch milliseconds.
    static let todayCall = #"{"call_id":"c1","start_timestamp":1794733200000,"call_cost":{"product_costs":[],"#
        + #""total_duration_seconds":60,"total_duration_unit_price":0.1,"combined_cost":125.5}}"#
    static let earlierCall = #"{"call_id":"c2","start_timestamp":1793707200000,"call_cost":{"product_costs":[],"#
        + #""total_duration_seconds":30,"total_duration_unit_price":0.1,"combined_cost":70}}"#
    static let ongoingCall = #"{"call_id":"c3","start_timestamp":1794766800000}"#

    @Test func addsUpCallCostsInCentsAcrossPages() async throws {
        let first = #"{"items":[\#(Self.ongoingCall),\#(Self.todayCall)],"has_more":true,"pagination_key":"k2"}"#
        let second = #"{"items":[\#(Self.earlierCall)],"has_more":false}"#
        let http = MockHTTPClient { request in
            let body = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return HTTPResponse(status: 200, json: body?["pagination_key"] as? String == "k2" ? second : first)
        }
        let snapshot = try await RetellProvider(http: http).fetchSpend(FakeKeys.credentials(.retell), now: testNow)
        #expect(http.requests.count == 2)
        let request = try #require(http.requests.first)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://api.retellai.com/v3/list-calls")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.retell)")
        let body = try #require(request.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["limit"] as? Int == 1000)
        #expect(body["sort_order"] as? String == "descending")
        let filter = try #require((body["filter_criteria"] as? [String: Any])?["start_timestamp"] as? [String: Any])
        #expect(filter["type"] as? String == "range")
        #expect(filter["op"] as? String == "bt")
        #expect(filter["value"] as? [Int64] == [1_793_491_200_000, 1_794_767_400_000])
        #expect(snapshot.today == usd("1.255"))
        #expect(snapshot.month == usd("1.955"))
        #expect(!snapshot.isEstimate)
    }

    @Test func tooManyPagesIsALabeledFloor() async throws {
        let page = #"{"items":[\#(Self.todayCall)],"has_more":true,"pagination_key":"more"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: page) }
        let snapshot = try await RetellProvider(http: http).fetchSpend(FakeKeys.credentials(.retell), now: testNow)
        #expect(http.requests.count == RetellProvider.maxPages)
        #expect(snapshot.isEstimate)
    }

    @Test func showsRetellsOwnMessage() async {
        let body = #"{"status":"error","message":"Invalid request format, please check API reference."}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400,
                                                  detail: "Invalid request format, please check API reference.")) {
            try await RetellProvider(http: http).fetchSpend(FakeKeys.credentials(.retell), now: testNow)
        }
    }
}
