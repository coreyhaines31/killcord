import Foundation
@testable import KillCordCore
import Testing

/// Saturday, Nov 15 2026, 6:30p UTC (10:30a in US Pacific).
let testNow = Date(timeIntervalSince1970: 1_794_767_400)

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

func json(_ name: String, status: Int = 200) throws -> HTTPResponse {
    HTTPResponse(status: status, headers: ["content-type": "application/json"], body: try fixture(name))
}

func decimal(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

func usd(_ text: String) -> Money {
    Money(decimal(text))
}

/// Fake keys only. Each is distinctive, so a leak is easy to search for.
enum FakeKeys {
    static let anthropic = "sk-ant-admin01-TEST-anthropic-secret-0001"
    static let openai = "sk-admin-TEST-openai-secret-0002"
    static let vercel = "vercel-TEST-token-secret-0003"
    static let cloudflare = "cf-TEST-token-secret-0004"
    static let twilio = "twilio-TEST-secret-0005"
    static let neon = "neon-TEST-key-secret-0006"
    static let googlePrivateKey = "-----BEGIN PRIVATE KEY-----\nTESTPRIVATEKEYgooglesecret0007\n-----END PRIVATE KEY-----\n"
    static let twilioSID = "ACaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    static var googleJSON: String {
        let object: [String: String] = [
            "type": "service_account", "project_id": "kc-billing", "private_key_id": "kid123",
            "private_key": googlePrivateKey, "client_email": "kill-cord@kc-billing.iam.gserviceaccount.com",
            "token_uri": "https://evil.example.com/token"
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    static func credentials(_ provider: ProviderID) -> ProviderCredentials {
        let values: [String: String] = switch provider {
        case .anthropic: ["apiKey": anthropic]
        case .openai: ["apiKey": openai]
        case .vercel: ["token": vercel, "teamID": "team_x"]
        case .cloudflare: ["token": cloudflare, "accountID": "0123456789abcdef0123456789abcdef"]
        case .twilio: ["accountSID": twilioSID, "apiKeySID": "SKbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "secret": twilio]
        case .neon: ["apiKey": neon, "orgID": "org-cool-cloud-123"]
        case .google: ["serviceAccountJSON": googleJSON,
                       "exportTable": "kc-billing.billing_export.gcp_billing_export_v1_0123AB_4567CD_89EF01",
                       "billingAccountID": "0123AB-4567CD-89EF01"]
        case .supabase: [:]
        }
        return ProviderCredentials(provider: provider, values: values)
    }

    /// Every fake secret, for leak checks.
    static let all = [anthropic, openai, vercel, cloudflare, twilio, neon, "TESTPRIVATEKEYgooglesecret0007",
                      "ya29.TEST-ACCESS-TOKEN"]
}

/// Stands in for RSA signing, which needs the Security framework. Records what it was asked to sign.
final class FakeSigner: RS256Signer, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [Data] = []

    var signed: [Data] { lock.withLock { messages } }

    func sign(_ message: Data, privateKeyPEM: String) throws -> Data {
        lock.withLock { messages.append(message) }
        return Data("fake-signature".utf8)
    }
}

/// Decodes a base64url segment of a JWT.
func base64URLDecode(_ text: String) -> Data? {
    var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    return Data(base64Encoded: base64)
}
