// The Mac's side of the Kill Cord Teams device API (killcord-cloud PR #30):
//   POST /api/v1/devices/start          {name} -> device_code, user_code, verification_uri(_complete), expires_in, interval
//   POST /api/v1/devices/token          {device_code} -> access_token, or 400 {error} (RFC 8628 names)
//   GET  /api/v1/me                     -> email, workspaces
//   GET  /api/v1/orgs/{id}/me/spend     -> month, total, units (amounts as exact decimal strings)
//   DELETE /api/v1/devices/current      -> 204
// The token travels only in the Authorization header and never appears in an error.
import Foundation

public enum TeamsError: Error, Equatable, Sendable, LocalizedError {
    case disabled
    case accessDenied
    case expired
    case invalidGrant
    case signedOut
    case notFound
    case rateLimited
    case server(Int)
    case network
    case badResponse

    /// Fixed text only: nothing from a response body, so a hostile or confused server can't echo a token here.
    public var errorDescription: String? {
        switch self {
        case .disabled: "Teams isn't turned on."
        case .accessDenied: "Sign-in was denied in the browser."
        case .expired: "The sign-in code expired. Start again."
        case .invalidGrant: "That sign-in can't be used. Start again."
        case .signedOut: "Signed out. Sign in again."
        case .notFound: "That workspace isn't available to you."
        case .rateLimited: "Too many sign-in attempts. Try again in a few minutes."
        case .server(let status): "Kill Cord's server answered with an error (\(status))."
        case .network: "Can't reach Kill Cord's server."
        case .badResponse: "Kill Cord's server sent something unexpected."
        }
    }
}

public struct DeviceSignIn: Sendable, Equatable {
    public var deviceCode: String
    public var userCode: String
    public var verificationURI: URL
    public var verificationURIComplete: URL
    public var expiresAt: Date
    public var interval: TimeInterval
}

public enum TokenPoll: Sendable, Equatable {
    case pending
    case signedIn
}

public struct TeamsWorkspace: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var role: String
    public var personal: Bool
}

public struct TeamsMe: Sendable, Equatable {
    public var email: String
    public var workspaces: [TeamsWorkspace]
}

public struct TeamsSpendUnit: Sendable, Equatable {
    public enum How: String, Sendable { case assigned, reported }
    public var label: String
    public var how: How
    public var amount: Decimal
}

public struct TeamsMySpend: Sendable, Equatable {
    public var month: String
    public var total: Decimal
    public var units: [TeamsSpendUnit]
}

public struct TeamsClient: Sendable {
    public let baseURL: URL
    private let http: HTTPClient
    private let tokens: TeamsTokenStore

    public init(baseURL: URL, http: HTTPClient, tokens: TeamsTokenStore) {
        self.baseURL = baseURL
        self.http = http
        self.tokens = tokens
    }

    public var isSignedIn: Bool { tokens.read() != nil }

    private func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await http.send(request)
        } catch {
            throw TeamsError.network
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TeamsError.badResponse
        }
        return json
    }

    private func jsonBody(_ value: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
    }

    public func startSignIn(deviceName: String, now: Date = Date()) async throws -> DeviceSignIn {
        let response = try await send(HTTPRequest(
            method: .post, url: url("api/v1/devices/start"),
            headers: ["content-type": "application/json"], body: jsonBody(["name": deviceName])))
        if response.status == 429 { throw TeamsError.rateLimited }
        guard response.status == 200 else { throw TeamsError.server(response.status) }
        let json = try object(response.body)
        guard let deviceCode = json["device_code"] as? String, let userCode = json["user_code"] as? String,
              let uri = (json["verification_uri"] as? String).flatMap(URL.init(string:)),
              let complete = (json["verification_uri_complete"] as? String).flatMap(URL.init(string:)),
              // NSNumber, not Double: Linux's JSONSerialization hands back integers as Int.
              let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue,
              let interval = (json["interval"] as? NSNumber)?.doubleValue,
              // The page the browser opens must be on the same server, so a confused or hostile
              // response can't send someone to a look-alike sign-in page.
              complete.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              complete.host?.lowercased() == baseURL.host?.lowercased(), complete.port == baseURL.port
        else { throw TeamsError.badResponse }
        return DeviceSignIn(deviceCode: deviceCode, userCode: userCode, verificationURI: uri,
                            verificationURIComplete: complete, expiresAt: now.addingTimeInterval(expiresIn),
                            interval: max(1, interval))
    }

    /// One poll. On success the token goes straight to the Keychain and is never returned.
    public func pollToken(deviceCode: String) async throws -> TokenPoll {
        let response = try await send(HTTPRequest(
            method: .post, url: url("api/v1/devices/token"),
            headers: ["content-type": "application/json"], body: jsonBody(["device_code": deviceCode])))
        let json = try object(response.body)
        if response.status == 200, let token = json["access_token"] as? String, !token.isEmpty {
            do { try tokens.save(token) } catch { throw TeamsError.badResponse }
            return .signedIn
        }
        switch json["error"] as? String {
        case "authorization_pending", "slow_down": return .pending
        case "access_denied": throw TeamsError.accessDenied
        case "expired_token": throw TeamsError.expired
        case "invalid_grant": throw TeamsError.invalidGrant
        default: throw TeamsError.server(response.status)
        }
    }

    private func authorized(_ path: String, method: HTTPRequest.Method = .get,
                            query: [URLQueryItem] = []) async throws -> HTTPResponse {
        guard let token = tokens.read() else { throw TeamsError.signedOut }
        let response = try await send(HTTPRequest(
            method: method, url: url(path).adding(query), headers: ["authorization": "Bearer " + token]))
        // The cloud answers a revoked or unknown token like a missing record.
        if response.status == 404 && path == "api/v1/me" { throw TeamsError.signedOut }
        if response.status == 404 { throw TeamsError.notFound }
        return response
    }

    public func me() async throws -> TeamsMe {
        let response = try await authorized("api/v1/me")
        guard response.status == 200 else { throw TeamsError.server(response.status) }
        let json = try object(response.body)
        guard let email = json["email"] as? String, let list = json["workspaces"] as? [[String: Any]] else {
            throw TeamsError.badResponse
        }
        let workspaces = try list.map { item -> TeamsWorkspace in
            guard let id = item["id"] as? String, let name = item["name"] as? String,
                  let role = item["role"] as? String else { throw TeamsError.badResponse }
            return TeamsWorkspace(id: id, name: name, role: role, personal: item["personal"] as? Bool ?? false)
        }
        return TeamsMe(email: email, workspaces: workspaces)
    }

    /// Your own spend in one workspace. Amounts arrive as exact decimal strings and stay Decimal.
    public func mySpend(workspaceID: String, month: String? = nil) async throws -> TeamsMySpend {
        guard UUID(uuidString: workspaceID) != nil else { throw TeamsError.notFound }
        let query = month.map { [URLQueryItem(name: "month", value: $0)] } ?? []
        let response = try await authorized("api/v1/orgs/\(workspaceID)/me/spend", query: query)
        guard response.status == 200 else { throw TeamsError.server(response.status) }
        let json = try object(response.body)
        guard let monthKey = json["month"] as? String, let total = (json["total"] as? String).flatMap(Money.decimal),
              let list = json["units"] as? [[String: Any]] else { throw TeamsError.badResponse }
        let units = try list.map { item -> TeamsSpendUnit in
            guard let label = item["label"] as? String,
                  let how = (item["how"] as? String).flatMap(TeamsSpendUnit.How.init(rawValue:)),
                  let amount = (item["amount"] as? String).flatMap(Money.decimal) else { throw TeamsError.badResponse }
            return TeamsSpendUnit(label: label, how: how, amount: amount)
        }
        return TeamsMySpend(month: monthKey, total: total, units: units)
    }

    /// Revokes this Mac's token on the server, then forgets it here even if the server can't be reached.
    public func signOut() async {
        defer { tokens.delete() }
        _ = try? await authorized("api/v1/devices/current", method: .delete)
    }
}
