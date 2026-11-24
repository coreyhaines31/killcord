// ElevenLabs credit allowance.
// Reference: https://elevenlabs.io/docs/api-reference/user/subscription/get
// Keys and their restrictions: https://elevenlabs.io/docs/overview/administration/workspaces/api-keys
// Errors: https://elevenlabs.io/docs/eleven-api/resources/errors
//
// GET https://api.elevenlabs.io/v1/user/subscription
//   headers: xi-api-key: <key>
//   200:     { "tier": "starter", "character_count": 1000, "character_limit": 10000,
//              "next_character_count_reset_unix": 1738356858 | null, "currency": "usd", … }
// The "character" fields hold credits. The docs don't name the key permission this call needs; user_read is
// the likely one. Errors: { "detail": { "type": "…", "message": "…" } } or { "detail": [ { "msg": "…" } ] }.
import Foundation

public struct ElevenLabsProvider: SpendProvider {
    public let id = ProviderID.elevenlabs
    static let subscriptionURL = URL(string: "https://api.elevenlabs.io/v1/user/subscription")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Give the key read access to User in ElevenLabs' key "
            + "settings.")
    }

    struct Subscription: Decodable {
        let characterCount: FlexibleDecimal
        let characterLimit: FlexibleDecimal
        let nextCharacterCountResetUnix: Double?

        enum CodingKeys: String, CodingKey {
            case characterCount = "character_count"
            case characterLimit = "character_limit"
            case nextCharacterCountResetUnix = "next_character_count_reset_unix"
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let plan = try await api.get(Subscription.self, Self.subscriptionURL, headers: ["xi-api-key": key])
        let used = plan.characterCount.value
        let limit = plan.characterLimit.value
        let balance = Balance(remaining: max(limit - used, 0), unit: .units("credits"), kind: .allowance,
                              limit: limit, used: used,
                              resetsAt: plan.nextCharacterCountResetUnix.map { Date(timeIntervalSince1970: $0) })
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
