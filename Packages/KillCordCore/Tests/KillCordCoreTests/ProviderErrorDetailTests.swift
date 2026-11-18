// swiftlint:disable line_length
import Foundation
@testable import KillCordCore
import Testing

@Suite struct ProviderErrorDetailTests {
    let request = HTTPRequest(url: URL(string: "https://api.example.com/v1/costs")!,
                              headers: ["x-api-key": FakeKeys.anthropic, "Authorization": "Bearer \(FakeKeys.openai)",
                                        "anthropic-version": "2023-06-01"])

    func detail(_ body: String) -> String? {
        ProviderErrorDetail.message(in: Data(body.utf8), sentWith: request)
    }

    @Test func readsTheCommonShapes() {
        #expect(detail(#"{"type":"error","error":{"type":"invalid_request_error","message":"Invalid date range: ending date must be after starting date"}}"#)
            == "Invalid date range: ending date must be after starting date")
        #expect(detail(#"{"success":false,"errors":[{"code":1003,"message":"Invalid account id"}]}"#) == "Invalid account id")
        #expect(detail(#"{"code":"","message":"org_id is required"}"#) == "org_id is required")
        #expect(detail(#"{"error":"bad_request"}"#) == "bad_request")
    }

    @Test func nilWhenThereIsNoMessage() {
        #expect(detail(#"{"error":{}}"#) == nil)
        #expect(detail("{}") == nil)
        #expect(detail("<html>Bad Request</html>") == nil)
        #expect(detail(#"{"error":{"message":"   "}}"#) == nil)
    }

    @Test func removesKeysTheRequestCarried() throws {
        let echoed = try #require(detail(#"{"error":{"message":"Key \#(FakeKeys.anthropic) and token \#(FakeKeys.openai) are not allowed here"}}"#))
        #expect(!echoed.contains(FakeKeys.anthropic))
        #expect(!echoed.contains(FakeKeys.openai))
        #expect(echoed == "Key [redacted] and token [redacted] are not allowed here")
    }

    @Test func collapsesWhitespaceAndCapsLength() throws {
        #expect(detail(#"{"message":"line one\n  line two"}"#) == "line one line two")
        let long = try #require(detail(#"{"message":"\#(String(repeating: "a", count: 500))"}"#))
        #expect(long.count == ProviderErrorDetail.maxLength)
    }
}

@Suite struct RejectedRequestTests {
    @Test func anthropicSurfacesItsOwnMessageOn400() async throws {
        let http = MockHTTPClient { _ in
            HTTPResponse(status: 400, json: #"{"type":"error","error":{"type":"invalid_request_error","message":"Invalid date range: ending date must be after starting date"}}"#)
        }
        do {
            try await AnthropicProvider(http: http).validate(FakeKeys.credentials(.anthropic), now: testNow)
            Issue.record("Expected an error")
        } catch let error as SpendError {
            #expect(error == .rejected(status: 400, detail: "Invalid date range: ending date must be after starting date"))
            #expect(error.message(for: .anthropic) == "Anthropic refused the request (HTTP 400): Invalid date range: ending date must be after starting date")
            #expect(!error.message(for: .anthropic).contains(FakeKeys.anthropic))
        }
    }

    @Test func keyAndScopeStatusesIgnoreTheBody() {
        #expect(SpendError.from(status: 401, missingScopeHint: "", detail: "nope") == .invalidKey)
        #expect(SpendError.from(status: 500, missingScopeHint: "", detail: "oops") == .server(status: 500))
        #expect(SpendError.from(status: 404, missingScopeHint: "") == .unexpectedStatus(404))
        #expect(SpendError.from(status: 404, missingScopeHint: "", detail: "Not found") == .rejected(status: 404, detail: "Not found"))
    }
}

// swiftlint:enable line_length
