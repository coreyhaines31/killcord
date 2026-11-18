// DataForSEO account data.
// Reference: https://docs.dataforseo.com/v3/appendix/user_data/
//
// GET https://api.dataforseo.com/v3/appendix/user_data
//   headers: Authorization: Basic base64(<API login>:<API password>) (from https://app.dataforseo.com/api-access)
//   200:     { "status_code": 20000, "tasks": [ { "status_code": 20000,
//              "result": [ { "login": "…", "timezone": "…", "money": { "total": 50, "balance": 41.25, … } } ] } ] }
// `money.balance` is the USD left of the prepaid deposit and `money.total` is what was deposited. The docs say
// the account isn't charged for this call. DataForSEO reports failures in `status_code` inside a 200 too:
// 20000 is success, 401xx is a login problem.
import Foundation

public struct DataForSEOProvider: SpendProvider {
    public let id = ProviderID.dataforseo
    static let userDataURL = URL(string: "https://api.dataforseo.com/v3/appendix/user_data")!

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the API login and password from the API Access page, "
            + "not your dashboard sign-in.")
    }

    struct Envelope: Decodable {
        let statusCode: Int
        let tasks: [Task]?

        struct Task: Decodable {
            let statusCode: Int
            let result: [UserData]?

            enum CodingKeys: String, CodingKey {
                case statusCode = "status_code"
                case result
            }
        }

        struct UserData: Decodable {
            let money: MoneyBlock
        }

        struct MoneyBlock: Decodable {
            let total: FlexibleDecimal?
            let balance: FlexibleDecimal
        }

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case tasks
        }
    }

    func request(_ credentials: ProviderCredentials) throws -> HTTPRequest {
        let login = try credentials.require("login")
        let password = try credentials.require("password")
        let token = Data("\(login):\(password)".utf8).base64EncodedString()
        return HTTPRequest(url: Self.userDataURL, headers: ["Authorization": "Basic \(token)"])
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let envelope = try api.decode(Envelope.self, from: try await api.send(try request(credentials)))
        let status = envelope.tasks?.first?.statusCode ?? envelope.statusCode
        guard envelope.statusCode == 20000, status == 20000 else {
            if (40100..<40200).contains(status) || (40100..<40200).contains(envelope.statusCode) {
                throw SpendError.invalidKey
            }
            throw SpendError.unexpectedResponse
        }
        guard let money = envelope.tasks?.first?.result?.first?.money else { throw SpendError.unexpectedResponse }
        let balance = Balance.usd(money.balance.value, kind: .prepaid, limit: money.total?.value)
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: balance, fetchedAt: now)
    }
}
