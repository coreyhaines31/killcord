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
    static let openrouter = "sk-or-v1-TEST-openrouter-secret-0008"
    static let dataforseo = "dfs-TEST-password-secret-0009"
    static let ahrefs = "ahrefs-TEST-key-secret-0010"
    static let firecrawl = "fc-TEST-firecrawl-secret-0011"
    static let treg = "treg-TEST-token-secret-0012"
    static let monid = "monid_test_TEST-secret-0013"
    static let custom = "custom-TEST-key-secret-0014"
    // Services in `ProviderInfo.moreBalanceProviders`.
    static let runpod = "rpa_TEST-runpod-secret-0101"
    static let deepinfra = "deepinfra-TEST-secret-0102"
    static let xapi = "AAAAAAAAAAAAAAAAAAAAA-TEST-xapi-bearer-0103"
    static let bfl = "bfl_TEST-bfl-secret-0104"
    static let digitalocean = "do-TEST-digitalocean-secret-0105"
    static let telnyx = "KEY-TEST-telnyx-secret-0106"
    static let luma = "luma-api-TEST-luma-secret-0107"
    static let heygen = "heygen-TEST-secret-0108"
    static let browseruse = "bu_TEST-browseruse-secret-0109"
    static let novita = "sk_TEST-novita-secret-0110"
    static let baseten = "bt-TEST-baseten-secret-0111"
    static let hunter = "hunter-TEST-secret-0112"
    static let zerobounce = "zerobounceTESTsecret0113abcd"
    static let vonage = "vonage-TEST-secret-0114"
    static let more: [String] = [
        vonage,
        zerobounce,
        hunter,
        baseten,
        novita,
        browseruse,
        heygen,
        luma,
        telnyx,
        digitalocean,
        bfl,
        xapi,
        runpod,
        deepinfra
    ]
    static let xai = "xai-mgmt-TEST-secret-0017"
    static let elevenlabs = "sk_TEST-elevenlabs-secret-0016"
    static let fal = "fal-TEST-key-id:fal-TEST-secret-0015"
    static let deepseek = "sk-TEST-deepseek-secret-0018"
    static let apify = "apify_api_TEST-secret-0019"
    static let tavily = "tvly-TEST-tavily-secret-0020"
    static let deepgram = "dg-TEST-deepgram-secret-0021"
    static let runway = "key_TESTrunwaysecret0022"
    static let serpapi = "serpapiTESTsecret0023abcdef"
    static let brightdata = "brightdata-TEST-secret-0024"
    static let scrapecreators = "scrapecreators-TEST-secret-0025"
    // Services in `ProviderInfo.batch3Providers`.
    static let stability = "sk-TEST-stability-secret-0026"
    static let moonshot = "sk-admin-TEST-kimi-secret-0027"
    static let exa = "exa-service-TEST-secret-0029"
    static let scrapingbee = "scrapingbee-TEST-secret-0030"
    static let scrapfly = "scrapfly-live-TEST-secret-0031"
    static let kie = "kie-TEST-secret-0032"
    static let bland = "org_s_TEST-bland-secret-0033"
    static let llamacloud = "llx-TEST-llamacloud-secret-0034"
    static let batch3 = [stability, moonshot, exa, scrapingbee, scrapfly, kie, bland, llamacloud]

    static var googleJSON: String {
        let object: [String: String] = [
            "type": "service_account", "project_id": "kc-billing", "private_key_id": "kid123",
            "private_key": googlePrivateKey, "client_email": "kill-cord@kc-billing.iam.gserviceaccount.com",
            "token_uri": "https://evil.example.com/token"
        ]
        // A fixed string dictionary is always JSON serializable.
        // swiftlint:disable:next force_try
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    // One case per provider.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
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
        case .runpod: ["apiKey": runpod]
        case .deepinfra: ["apiKey": deepinfra]
        case .xapi: ["apiKey": xapi]
        case .bfl: ["apiKey": bfl]
        case .digitalocean: ["apiKey": digitalocean]
        case .telnyx: ["apiKey": telnyx]
        case .luma: ["apiKey": luma]
        case .heygen: ["apiKey": heygen]
        case .browseruse: ["apiKey": browseruse]
        case .novita: ["apiKey": novita]
        case .baseten: ["apiKey": baseten]
        case .hunter: ["apiKey": hunter]
        case .zerobounce: ["apiKey": zerobounce]
        case .vonage: ["apiKey": "a1b2c3d4", "apiSecret": vonage]
        case .openrouter: ["apiKey": openrouter]
        case .dataforseo: ["login": "kc-test@example.com", "password": dataforseo]
        case .ahrefs: ["apiKey": ahrefs]
        case .firecrawl: ["apiKey": firecrawl]
        case .treg: ["token": treg]
        case .monid: ["apiKey": monid]
        case .fal: ["apiKey": fal]
        case .elevenlabs: ["apiKey": elevenlabs]
        case .xai: ["managementKey": xai, "teamID": "65c1e471-205f-4566-9c5a-07198bcdf4ce"]
        case .deepseek: ["apiKey": deepseek]
        case .apify: ["apiKey": apify]
        case .tavily: ["apiKey": tavily]
        case .deepgram: ["apiKey": deepgram]
        case .runway: ["apiKey": runway]
        case .serpapi: ["apiKey": serpapi]
        case .brightdata: ["apiKey": brightdata]
        case .scrapecreators: ["apiKey": scrapecreators]
        case .stability: ["apiKey": stability]
        case .moonshot: ["apiKey": moonshot]
        case .exa: ["apiKey": exa]
        case .scrapingbee: ["apiKey": scrapingbee]
        case .scrapfly: ["apiKey": scrapfly]
        case .kie: ["apiKey": kie]
        case .bland: ["apiKey": bland]
        case .llamacloud: ["apiKey": llamacloud]
        case .custom: ["serviceName": "Example", "url": "https://api.example.com/v1/balance", "key": custom,
                       "remainingPath": "data.balance"]
        // Values long enough not to turn up by chance inside an id or a date.
        case .manual: ["serviceName": "Truelist", "plan": "Starter", "price": "49.25", "renewsOn": "2026-11-03",
                       "allowance": "12345"]
        }
        return ProviderCredentials(provider: provider, values: values)
    }

    /// Every fake secret, for leak checks.
    static let all = [anthropic, openai, vercel, cloudflare, twilio, neon, "TESTPRIVATEKEYgooglesecret0007",
                      "ya29.TEST-ACCESS-TOKEN", openrouter, dataforseo, ahrefs, firecrawl, treg, monid, custom,
                      fal, elevenlabs, xai, deepseek, apify, tavily, deepgram, runway, serpapi, brightdata, scrapecreators]
        + more + batch3
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

extension UUID {
    /// A fixed connection id per provider, for tests with one connection each.
    static func of(_ provider: ProviderID, _ number: Int = 1) -> UUID {
        let index = ProviderID.allCases.firstIndex(of: provider)!
        return UUID(uuidString: String(format: "00000000-0000-0000-%04d-%012d", index, number))!
    }
}

/// One connection per provider, with the `.of(provider)` ids.
func oneEach(_ providers: [ProviderID]) -> ConnectionRegistry {
    ConnectionRegistry(records: providers.map { ConnectionRecord(id: .of($0), provider: $0, createdAt: testNow) })
}
