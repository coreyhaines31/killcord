// swiftlint:disable line_length
// Fixtures follow Baseten's documented schema:
// https://docs.baseten.co/reference/management-api/billing/gets-billing-usage-summary-for-a-date-range
import Foundation
@testable import KillCordCore
import Testing

@Suite struct BasetenProviderTests {
    @Test func asksForTheMonthAndTheDayInWholeUTCDays() async throws {
        let http = MockHTTPClient(routes: ["/v1/billing/usage_summary": try json("baseten-usage-summary.json")])
        let snapshot = try await BasetenProvider(http: http).fetchSpend(FakeKeys.credentials(.baseten), now: testNow)
        #expect(http.requests.count == 2)
        let urls = http.requests.map(\.url.absoluteString)
        #expect(urls == [
            "https://api.baseten.co/v1/billing/usage_summary?start_date=2026-11-01T00:00:00Z&end_date=2026-11-16T00:00:00Z",
            "https://api.baseten.co/v1/billing/usage_summary?start_date=2026-11-15T00:00:00Z&end_date=2026-11-16T00:00:00Z"
        ])
        #expect(http.requests.allSatisfy { $0.method == .get && $0.headers["Authorization"] == "Bearer \(FakeKeys.baseten)" })
        // Dedicated 10.00 after credits, plus Model APIs 3.25.
        #expect(snapshot.month == usd("13.25"))
        #expect(snapshot.today == usd("13.25"))
    }

    @Test func noUsageIsZero() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"dedicated_usage":null,"training_usage":null,"model_apis_usage":null}"#) }
        let snapshot = try await BasetenProvider(http: http).fetchSpend(FakeKeys.credentials(.baseten), now: testNow)
        #expect(snapshot.month == usd("0") && snapshot.today == usd("0"))
    }

    @Test func aKeyThatCantReadBillingSaysWhichToUse() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: #"{"error":"Forbidden"}"#) }
        do {
            _ = try await BasetenProvider(http: http).fetchSpend(FakeKeys.credentials(.baseten), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error.message(for: .baseten).contains("personal API key"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func aMissingKeyNeverReachesTheNetwork() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        await #expect(throws: SpendError.notConfigured) {
            try await BasetenProvider(http: http).fetchSpend(ProviderCredentials(provider: .baseten, values: [:]),
                                                             now: testNow)
        }
        #expect(http.requests.isEmpty)
    }
}
// swiftlint:enable line_length
