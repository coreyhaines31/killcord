// swiftlint:disable line_length
// Fixtures follow Novita AI's documented example: https://docs.novita.ai/api-reference/basic-get-user-balance
import Foundation
@testable import KillCordCore
import Testing

@Suite struct NovitaProviderTests {
    @Test func convertsTenThousandthsOfADollar() async throws {
        let http = MockHTTPClient(routes: ["/openapi/v1/billing/balance/detail": try json("novita-balance-detail.json")])
        let snapshot = try await NovitaProvider(http: http).fetchSpend(FakeKeys.credentials(.novita), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.novita.ai/openapi/v1/billing/balance/detail")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.novita)")
        // "10000 = $1.00", so 1000000 is $100.
        #expect(snapshot.balance == .usd(100))
    }

    @Test func keepsFractionsOfACent() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: #"{"availableBalance":"12345"}"#) }
        let snapshot = try await NovitaProvider(http: http).fetchSpend(FakeKeys.credentials(.novita), now: testNow)
        #expect(snapshot.balance == .usd(decimal("1.2345")))
    }

    @Test func aRejectedKeyIsInvalid() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 401, json: #"{"code":401,"reason":"INVALID_API_KEY","message":"invalid api key"}"#) }
        await #expect(throws: SpendError.invalidKey) {
            try await NovitaProvider(http: http).fetchSpend(FakeKeys.credentials(.novita), now: testNow)
        }
    }
}
// swiftlint:enable line_length
