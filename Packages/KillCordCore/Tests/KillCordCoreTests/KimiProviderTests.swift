// Fixtures follow Kimi's documented responses:
// Admin: https://platform.kimi.ai/docs/admin-api/billing-account
// Inference key: https://platform.kimi.ai/docs/api/balance
import Foundation
@testable import KillCordCore
import Testing

@Suite struct KimiProviderTests {
    @Test func anAdminKeyReadsTheOrganizationBalanceInMilliCents() async throws {
        let http = MockHTTPClient(routes: ["/v1/admin/organizations/account": try json("kimi-admin-account.json")])
        let snapshot = try await KimiProvider(http: http).fetchSpend(FakeKeys.credentials(.moonshot), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.moonshot.ai/v1/admin/organizations/account")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.moonshot)")
        #expect(snapshot.balance == .usd(decimal("49.58894")))
    }

    @Test func anInferenceKeyReadsTheUserBalance() async throws {
        let http = MockHTTPClient(routes: ["/v1/users/me/balance": try json("kimi-users-me-balance.json")])
        let credentials = ProviderCredentials(provider: .moonshot, values: ["apiKey": "sk-TEST-kimi-inference-0028"])
        let snapshot = try await KimiProvider(http: http).fetchSpend(credentials, now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.url.absoluteString == "https://api.moonshot.ai/v1/users/me/balance")
        #expect(request.headers["Authorization"] == "Bearer sk-TEST-kimi-inference-0028")
        #expect(snapshot.balance == .usd(decimal("49.58894")))
    }

    @Test func aNonZeroCodeIsAnUnexpectedResponse() async {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 200, json: #"{"code":5,"data":{"available_balance":0},"scode":"0x5","status":false}"#)
        }
        let credentials = ProviderCredentials(provider: .moonshot, values: ["apiKey": "sk-TEST-kimi-inference-0028"])
        await #expect(throws: SpendError.unexpectedResponse) {
            try await KimiProvider(http: http).fetchSpend(credentials, now: testNow)
        }
    }

    @Test func aMissingScopeNamesBillingRead() async {
        let body = #"{"error":{"type":"permission_error","code":"insufficient_scope","message":"Missing scope.","#
            + #""param":null,"request_id":"r1"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: body) }
        do {
            _ = try await KimiProvider(http: http).fetchSpend(FakeKeys.credentials(.moonshot), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error == .missingScope(hint: "Give the Admin key the billing:read scope."))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }
}
