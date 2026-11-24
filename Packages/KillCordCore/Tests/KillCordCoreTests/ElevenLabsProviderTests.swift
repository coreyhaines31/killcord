// swiftlint:disable line_length
// Fixtures follow ElevenLabs' documented response: https://elevenlabs.io/docs/api-reference/user/subscription/get
// Error shapes: https://elevenlabs.io/docs/eleven-api/resources/errors
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ElevenLabsProviderTests {
    @Test func readsCreditsLeftOfThePlanAndTheReset() async throws {
        let http = MockHTTPClient(routes: ["/v1/user/subscription": try json("elevenlabs-user-subscription.json")])
        let snapshot = try await ElevenLabsProvider(http: http).fetchSpend(FakeKeys.credentials(.elevenlabs), now: testNow)
        let request = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(request.url.absoluteString == "https://api.elevenlabs.io/v1/user/subscription")
        #expect(request.headers["xi-api-key"] == FakeKeys.elevenlabs)
        let balance = try #require(snapshot.balance)
        #expect(balance.remaining == 58_750)
        #expect(balance.limit == 100_000)
        #expect(balance.used == 41_250)
        #expect(balance.unit == .units("credits"))
        #expect(balance.kind == .allowance)
        #expect(balance.resetsAt == Date(timeIntervalSince1970: 1_796_083_200))
    }

    @Test func overTheLimitShowsNoneLeftNotANegative() async throws {
        let body = #"{"tier":"free","character_count":10200,"character_limit":10000,"next_character_count_reset_unix":null}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 200, json: body) }
        let snapshot = try await ElevenLabsProvider(http: http).fetchSpend(FakeKeys.credentials(.elevenlabs), now: testNow)
        #expect(snapshot.balance?.remaining == 0)
        #expect(snapshot.balance?.resetsAt == nil)
    }

    @Test func showsElevenLabsOwnMessageFromDetail() async {
        let body = #"{"detail":{"type":"validation_error","code":"invalid_parameters","message":"Workspace is not active","status":"invalid_parameters"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: body) }
        await #expect(throws: SpendError.rejected(status: 400, detail: "Workspace is not active")) {
            try await ElevenLabsProvider(http: http).fetchSpend(FakeKeys.credentials(.elevenlabs), now: testNow)
        }
    }

    @Test func aRestrictedKeyIsAMissingPermission() async {
        let body = #"{"detail":{"type":"authorization_error","code":"insufficient_permissions","message":"The API key you used is missing the permission user_read"}}"#
        let http = MockHTTPClient { _ in HTTPResponse(status: 403, json: body) }
        await #expect(throws: SpendError.missingScope(hint: "Give the key read access to User in ElevenLabs' key settings.")) {
            try await ElevenLabsProvider(http: http).fetchSpend(FakeKeys.credentials(.elevenlabs), now: testNow)
        }
    }
}
// swiftlint:enable line_length
