// Fixtures follow Luma's documented examples: https://docs.agents.lumalabs.ai/guides/usage/
import Foundation
@testable import KillCordCore
import Testing

@Suite struct LumaProviderTests {
    @Test func readsTheTeamsCreditBalance() async throws {
        let http = MockHTTPClient(routes: ["/v1/credits": try json("luma-credits.json")])
        let snapshot = try await LumaProvider(http: http).fetchSpend(FakeKeys.credentials(.luma), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://agents.lumalabs.ai/v1/credits")
        #expect(request.headers["Authorization"] == "Bearer \(FakeKeys.luma)")
        let balance = try #require(snapshot.balance)
        #expect(balance.remaining == 49512 && balance.unit == .units("credits"))
        // Luma: "Do not assume a default rate."
        #expect(balance.dollarsPerUnit == nil)
    }

    @Test func showsLumasErrorMessage() async {
        let body = #"{"detail":{"code":"REQUEST.INVALID","message":"The request failed validation","request_id":"r1"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 422, json: body) }
        await #expect(throws: SpendError.rejected(status: 422, detail: "The request failed validation")) {
            try await LumaProvider(http: http).fetchSpend(FakeKeys.credentials(.luma), now: testNow)
        }
    }

    @Test func anAdminKeyIsRefusedWithAHint() async {
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: #"{"detail":"Forbidden"}"#) }
        do {
            _ = try await LumaProvider(http: http).fetchSpend(FakeKeys.credentials(.luma), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error.message(for: .luma).contains("Admin read-only keys"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }
}
