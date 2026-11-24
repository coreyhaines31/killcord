// Fixtures follow DigitalOcean's OpenAPI spec:
// https://github.com/digitalocean/openapi/blob/main/specification/resources/billing/models/balance.yml
import Foundation
@testable import KillCordCore
import Testing

@Suite struct DigitalOceanProviderTests {
    @Test func readsMonthToDateUsageAndWhenItWasGenerated() async throws {
        let http = MockHTTPClient(routes: ["/v2/customers/my/balance": try json("digitalocean-customer-balance.json")])
        let snapshot = try await DigitalOceanProvider(http: http).fetchSpend(FakeKeys.credentials(.digitalocean),
                                                                            now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.digitalocean.com/v2/customers/my/balance")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.digitalocean)")
        #expect(snapshot.month == usd("11.21"))
        #expect(snapshot.today == nil && snapshot.balance == nil)
        #expect(snapshot.dataAsOf == ISO8601.date("2026-11-15T18:00:00Z"))
    }

    @Test func aTokenWithoutBillingReadNamesTheScope() async {
        let body = #"{"id":"forbidden","message":"You are not authorized to perform this operation"}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: body) }
        do {
            _ = try await DigitalOceanProvider(http: http).fetchSpend(FakeKeys.credentials(.digitalocean), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error.message(for: .digitalocean).contains("billing:read"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }

    @Test func aMissingKeyNeverReachesTheNetwork() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200) }
        await #expect(throws: SpendError.notConfigured) {
            try await DigitalOceanProvider(http: http).fetchSpend(
                ProviderCredentials(provider: .digitalocean, values: [:]), now: testNow)
        }
        #expect(http.requests.isEmpty)
        #expect(ProviderID.digitalocean.keyPower == .readOnly)
    }
}
