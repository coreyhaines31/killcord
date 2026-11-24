// Resend reports quotas in response headers: https://resend.com/docs/api-reference/rate-limit
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ResendProviderTests {
    @Test func readsTheQuotaHeadersFromAOneDomainList() async throws {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"object":"list","has_more":false,"data":[]}"#,
                         headers: ["x-resend-monthly-quota": "1234", "x-resend-daily-quota": "56"])
        }
        let snapshot = try await ResendProvider(http: http).fetchSpend(FakeKeys.credentials(.resend), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.resend.com/domains?limit=1")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.resend)")
        #expect(request.headers["User-Agent"] == "KillCord")
        #expect(snapshot.usage == [
            UsageMetric(id: "monthEmails", name: "Emails this month", value: 1234, unit: "emails"),
            UsageMetric(id: "dayEmails", name: "Emails today", value: 56, unit: "emails")
        ])
    }

    @Test func paidPlansHaveNoDailyCount() async throws {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"data":[]}"#, headers: ["x-resend-monthly-quota": "80000"])
        }
        let snapshot = try await ResendProvider(http: http).fetchSpend(FakeKeys.credentials(.resend), now: testNow)
        #expect(snapshot.usage.map(\.id) == ["monthEmails"])
    }

    @Test func aWrongKeyIsRejected() async {
        let body = #"{"name":"validation_error","statusCode":401,"message":"API key is invalid"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 401, json: body) }
        await #expect(throws: SpendError.invalidKey) {
            try await ResendProvider(http: http).fetchSpend(FakeKeys.credentials(.resend), now: testNow)
        }
    }

    @Test func noQuotaHeaderIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"data":[]}"#) }
        await #expect(throws: SpendError.unexpectedResponse) {
            try await ResendProvider(http: http).fetchSpend(FakeKeys.credentials(.resend), now: testNow)
        }
    }

    @Test func aSendingAccessKeyIsRefused() async {
        let body = #"{"name":"restricted_api_key","statusCode":401,"#
            + #""message":"This API key is restricted to only send emails."}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 401, json: body) }
        await #expect(throws: SpendError.missingScope(hint: ResendProvider.missingScopeHint)) {
            try await ResendProvider(http: http).fetchSpend(FakeKeys.credentials(.resend), now: testNow)
        }
    }
}
