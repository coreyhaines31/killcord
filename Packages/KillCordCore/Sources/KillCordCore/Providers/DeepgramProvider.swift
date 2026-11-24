// Deepgram project balances.
// Reference: https://developers.deepgram.com/reference/manage/billing/list (get all balances)
// Projects: https://developers.deepgram.com/reference/manage/projects/list
// Roles: https://developers.deepgram.com/guides/deep-dives/working-with-roles (billing:read is Admin and Owner)
//
// GET https://api.deepgram.com/v1/projects                      (only when no project ID is saved)
//   200: { "projects": [ { "project_id": "…", "name": "…" } ] }
// GET https://api.deepgram.com/v1/projects/{project_id}/balances
//   headers: Authorization: Token <API key>
//   200: { "balances": [ { "balance_id": "…", "amount": 12.5, "units": "USD", "purchase_order_id": "…" } ] }
// "A list of outstanding balances": Kill Cord adds up the USD ones. Errors are a string, the older
// { err_code, err_msg }, or { category, message, details }.
import Foundation

public struct DeepgramProvider: SpendProvider {
    public let id = ProviderID.deepgram
    static let base = URL(string: "https://api.deepgram.com/v1/projects")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a key with the Admin or Owner role: Deepgram gives "
            + "billing:read to those roles only.")
    }

    struct Projects: Decodable {
        let projects: [Project]

        struct Project: Decodable {
            let projectID: String

            enum CodingKeys: String, CodingKey {
                case projectID = "project_id"
            }
        }
    }

    struct Balances: Decodable {
        let balances: [Entry]

        struct Entry: Decodable {
            let amount: FlexibleDecimal?
            let units: String?
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let headers = ["Authorization": "Token \(try credentials.require("apiKey"))"]
        let project = try await projectID(credentials, headers: headers)
        let url = Self.base.appendingPathComponent(project).appendingPathComponent("balances")
        let response = try await api.get(Balances.self, url, headers: headers)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: try Self.balance(response.balances),
                             fetchedAt: now)
    }

    func projectID(_ credentials: ProviderCredentials, headers: [String: String]) async throws -> String {
        if let saved = credentials["projectID"] {
            // It goes into the path, so only the characters an ID can have.
            guard FieldFormat.isIdentifier(saved) else {
                throw SpendError.requiresSetup("the project ID doesn't look right. Copy it from the project's "
                    + "settings.")
            }
            return saved
        }
        let projects = try await api.get(Projects.self, Self.base, headers: headers).projects
        guard projects.count == 1, let only = projects.first, FieldFormat.isIdentifier(only.projectID) else {
            throw SpendError.requiresSetup(projects.isEmpty
                ? "this key can't see any project. Use a key from the project you want to watch."
                : "this key can see \(projects.count) projects. Add the project ID to choose one.")
        }
        return only.projectID
    }

    /// USD balances added up. An empty list means nothing is outstanding, so nothing is left.
    static func balance(_ entries: [Balances.Entry]) throws -> Balance {
        let usd = entries.filter { $0.units?.uppercased() == "USD" }
        if !usd.isEmpty || entries.isEmpty {
            return .usd(usd.reduce(Decimal(0)) { $0 + ($1.amount?.value ?? 0) })
        }
        // Not dollars: show them in their own unit when there's only one kind.
        let units = Set(entries.compactMap { $0.units?.lowercased() })
        guard units.count == 1, let unit = units.first,
              unit.range(of: "^[a-z ]{1,20}$", options: .regularExpression) != nil else {
            throw SpendError.unexpectedResponse
        }
        return Balance(remaining: entries.reduce(Decimal(0)) { $0 + ($1.amount?.value ?? 0) }, unit: .units(unit))
    }
}
