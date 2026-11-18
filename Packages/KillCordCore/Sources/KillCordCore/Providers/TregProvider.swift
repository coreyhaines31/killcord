// treg prepaid balance.
// Public docs: https://treg.to/skill.md (the `treg balance` command, X-Treg-Token, X-Treg-Org).
// The HTTP routes come from the official tools-registry package (0.31.0 on PyPI): `treg/routers/auth.py`
// (`GET /auth/me`) and `treg/routers/billing.py` (`GET /orgs/{org_id}/balance`). There's no docs page for
// them, so a change on treg's side shows as "unexpected response".
//
// GET https://treg.to/auth/me
//   headers: X-Treg-Token: <token>, and X-Treg-Org: <team slug> for a personal sign-in token
//   200:     { "email": "…", "org_id": 42, "org": "acme", "role": "viewer", … }
// GET https://treg.to/orgs/{org_id}/balance
//   200:     { "org_id": 42, "balance_micro": 12345678, "balance_usd": 12.345678,
//              "holds": [ … ], … }   (holds are reservations for calls still running; not shown)
// Amounts are integer micro-USD; treg says never to compute with `balance_usd`. Any member can read it.
// Reading the balance can also start treg's auto top-up when it's on and the balance is under its trigger.
import Foundation

public struct TregProvider: SpendProvider {
    public let id = ProviderID.treg
    static let base = URL(string: "https://treg.to")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a token for a team you're a member of. A personal "
            + "token also needs the team slug.")
    }

    struct Identity: Decodable {
        let orgID: Int?

        enum CodingKeys: String, CodingKey {
            case orgID = "org_id"
        }
    }

    struct OrgBalance: Decodable {
        let balanceMicro: Int64

        enum CodingKeys: String, CodingKey {
            case balanceMicro = "balance_micro"
        }
    }

    func headers(_ credentials: ProviderCredentials) throws -> [String: String] {
        var headers = ["X-Treg-Token": try credentials.require("token")]
        if let org = credentials["org"] {
            guard org.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil else {
                throw SpendError.notConfigured
            }
            headers["X-Treg-Org"] = org
        }
        return headers
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let headers = try headers(credentials)
        let identity = try await api.get(Identity.self, Self.base.appendingPathComponent("auth/me"), headers: headers)
        // A personal token with no team chosen has no org.
        guard let orgID = identity.orgID else {
            throw SpendError.requiresSetup("add your team's slug, or use a team token.")
        }
        let url = Self.base.appendingPathComponent("orgs/\(orgID)/balance")
        let org = try await api.get(OrgBalance.self, url, headers: headers)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: .usd(Self.usd(org.balanceMicro)),
                             fetchedAt: now)
    }

    static func usd(_ micro: Int64) -> Decimal { Decimal(micro) / 1_000_000 }
}
