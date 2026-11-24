// swiftlint:disable line_length
// Fixtures follow HeyGen's documented schema and examples: https://developers.heygen.com/reference/get-current-user
import Foundation
@testable import KillCordCore
import Testing

@Suite struct HeyGenProviderTests {
    func provider(_ body: String) -> (HeyGenProvider, MockHTTPClient) {
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        return (HeyGenProvider(http: http), http)
    }

    @Test func readsAWalletBalanceWithTheKeyHeader() async throws {
        let http = MockHTTPClient(routes: ["/v3/users/me": try json("heygen-users-me-wallet.json")])
        let snapshot = try await HeyGenProvider(http: http).fetchSpend(FakeKeys.credentials(.heygen), now: testNow)
        let request = try #require(http.requests.first)
        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://api.heygen.com/v3/users/me")
        #expect(request.headers["x-api-key"] == FakeKeys.heygen)
        #expect(snapshot.balance == .usd(decimal("125.5")))
    }

    @Test func anEnterpriseWalletIsInCredits() async throws {
        let (heygen, _) = provider(#"{"data":{"username":"u","email":null,"first_name":null,"last_name":null,"billing_type":"wallet","wallet":{"currency":"credits","remaining_balance":900}}}"#)
        let balance = try #require(try await heygen.fetchSpend(FakeKeys.credentials(.heygen), now: testNow).balance)
        #expect(balance == Balance(remaining: 900, unit: .units("credits")))
    }

    @Test func usageBasedShowsWhatIsLeftUnderTheCap() async throws {
        let (heygen, _) = provider(#"{"data":{"username":"u","email":null,"first_name":null,"last_name":null,"billing_type":"usage_based","usage_based":{"spending_current_usd":42.5,"spending_cap_usd":100,"included_credits":4444,"remaining_credits":4426.9}}}"#)
        let balance = try #require(try await heygen.fetchSpend(FakeKeys.credentials(.heygen), now: testNow).balance)
        #expect(balance == .usd(decimal("57.5"), kind: .allowance, limit: 100, used: decimal("42.5")))
        let caps = await heygen.verifyCaps(FakeKeys.credentials(.heygen), now: testNow)
        #expect(caps.map(\.capID) == [HeyGenProvider.spendingCapID])
        guard case .on(let detail) = caps.first?.status else {
            Issue.record("Expected on, got \(caps)")
            return
        }
        #expect(detail.contains("$100.00"))
    }

    @Test func usageBasedWithNoCapSaysSo() async {
        let (heygen, _) = provider(#"{"data":{"username":"u","email":null,"first_name":null,"last_name":null,"billing_type":"usage_based","usage_based":{"spending_current_usd":42.5,"spending_cap_usd":null}}}"#)
        do {
            _ = try await heygen.fetchSpend(FakeKeys.credentials(.heygen), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            guard case .planNotSupported = error else {
                Issue.record("Unexpected \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected \(error)")
        }
        let caps = await heygen.verifyCaps(FakeKeys.credentials(.heygen), now: testNow)
        guard case .off = caps.first?.status else {
            Issue.record("Expected off, got \(caps)")
            return
        }
    }

    @Test func subscriptionCreditsResetOnTheirDate() async throws {
        let (heygen, _) = provider(#"{"data":{"username":"u","email":null,"first_name":null,"last_name":null,"billing_type":"subscription","subscription":{"plan":"team","credits":{"premium_credits":{"remaining":500,"resets_at":"2026-12-01T00:00:00Z"},"add_on_credits":{"remaining":20}}}}}"#)
        let balance = try #require(try await heygen.fetchSpend(FakeKeys.credentials(.heygen), now: testNow).balance)
        #expect(balance.remaining == 520 && balance.kind == .allowance)
        #expect(balance.resetsAt == ISO8601.date("2026-12-01T00:00:00Z"))
    }

    @Test func autoReloadOnMeansTheWalletDoesNotStop() async throws {
        let http = MockHTTPClient(routes: ["/v3/users/me": try json("heygen-users-me-wallet.json")])
        let caps = await HeyGenProvider(http: http).verifyCaps(FakeKeys.credentials(.heygen), now: testNow)
        #expect(caps.map(\.capID) == [HeyGenProvider.autoReloadCapID])
        guard case .off(let detail) = caps.first?.status else {
            Issue.record("Expected off, got \(caps)")
            return
        }
        #expect(detail.contains("$10.00") && detail.contains("$50.00"))
    }

    @Test func aKeyWithoutAccountReadNamesTheScope() async {
        let body = #"{"error":{"code":"insufficient_api_key_scope","message":"This API key is missing a required scope."}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: body) }
        do {
            _ = try await HeyGenProvider(http: http).fetchSpend(FakeKeys.credentials(.heygen), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error.message(for: .heygen).contains("account:read"))
        } catch {
            Issue.record("Unexpected \(error)")
        }
    }
}
// swiftlint:enable line_length
