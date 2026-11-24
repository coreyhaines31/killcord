// Fixtures follow Postmark's documented response: https://postmarkapp.com/developer/api/stats-api
import Foundation
@testable import KillCordCore
import Testing

@Suite struct PostmarkProviderTests {
    @Test func readsThisMonthsAndTodaysSentCounts() async throws {
        let http = MockHTTPClient(routes: ["/stats/outbound/sends": try json("postmark-outbound-sends.json")])
        let snapshot = try await PostmarkProvider(http: http).fetchSpend(FakeKeys.credentials(.postmark), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString
            == "https://api.postmarkapp.com/stats/outbound/sends?fromdate=2026-11-01&todate=2026-11-15")
        #expect(request.headers["X-Postmark-Server-Token"] == FakeKeys.postmark)
        #expect(request.headers["Accept"] == "application/json")
        #expect(snapshot.usage == [
            UsageMetric(id: "monthSent", name: "Emails sent this month", value: 350, unit: "emails"),
            UsageMetric(id: "daySent", name: "Emails sent today", value: 50, unit: "emails")
        ])
    }

    @Test func aQuietDayIsZero() async throws {
        let body = #"{"Days":[{"Date":"2026-11-02","Sent":4}],"Sent":4}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await PostmarkProvider(http: http).fetchSpend(FakeKeys.credentials(.postmark), now: testNow)
        #expect(snapshot.usage.last?.value == 0)
    }

    @Test func showsPostmarksOwnMessage() async {
        let body = #"{"ErrorCode":10,"Message":"Request does not contain a valid Server token."}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 422, json: body) }
        await #expect(throws: SpendError.rejected(status: 422, detail: "Request does not contain a valid Server token.")) {
            try await PostmarkProvider(http: http).fetchSpend(FakeKeys.credentials(.postmark), now: testNow)
        }
    }
}
