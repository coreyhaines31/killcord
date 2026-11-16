// Google OAuth 2.0 for service accounts, without a Google SDK.
// Docs: https://developers.google.com/identity/protocols/oauth2/service-account
// Key guidance: https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys
//
// 1. Build a JWT: header { alg: RS256, typ: JWT, kid: private_key_id }, claims { iss: client_email,
//    scope, aud: https://oauth2.googleapis.com/token, iat, exp (at most iat + 1 hour) }.
// 2. Sign it with the service account's RSA key (RSASSA-PKCS1-v1_5, SHA-256).
// 3. POST grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=<jwt>, form-encoded, to
//    https://oauth2.googleapis.com/token. The answer is { access_token, expires_in, token_type: "Bearer" }.
// The token endpoint is fixed: a pasted key file's `token_uri` is never trusted, so a signed assertion
// can only go to Google.
import Foundation

/// The parts of a service account JSON key file Kill Cord uses.
struct GoogleServiceAccount: Decodable, Sendable {
    let type: String?
    let projectID: String?
    let privateKeyID: String?
    let privateKey: String
    let clientEmail: String

    enum CodingKeys: String, CodingKey {
        case type
        case projectID = "project_id"
        case privateKeyID = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
    }

    static func parse(_ json: String) throws -> GoogleServiceAccount {
        guard let account = try? JSONDecoder().decode(GoogleServiceAccount.self, from: Data(json.utf8)),
              account.type == nil || account.type == "service_account",
              account.privateKey.contains("PRIVATE KEY")
        else { throw SpendError.invalidKey }
        return account
    }
}

/// Signs bytes with an RSA private key in PEM, RSASSA-PKCS1-v1_5 with SHA-256. On macOS this is
/// `SecurityRS256Signer`; tests use a fake, since Linux has no Security framework.
public protocol RS256Signer: Sendable {
    func sign(_ message: Data, privateKeyPEM: String) throws -> Data
}

/// Used where no signer exists (Linux builds of Core). Google can't connect there.
public struct UnavailableRS256Signer: RS256Signer {
    public init() {}

    public func sign(_ message: Data, privateKeyPEM: String) throws -> Data {
        throw SpendError.requiresSetup("signing Google service account keys needs macOS.")
    }
}

#if canImport(Security)
import Security

public struct SecurityRS256Signer: RS256Signer {
    public init() {}

    public func sign(_ message: Data, privateKeyPEM: String) throws -> Data {
        let der = try PEM.rsaPrivateKey(privateKeyPEM)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw SpendError.invalidKey
        }
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData,
                                                    &error) as Data? else {
            throw SpendError.invalidKey
        }
        return signature
    }
}
#endif

public enum PlatformRS256Signer {
    public static func make() -> RS256Signer {
        #if canImport(Security)
        SecurityRS256Signer()
        #else
        UnavailableRS256Signer()
        #endif
    }
}

/// Just enough PEM and DER to hand an RSA key to the Security framework, which wants PKCS #1, while Google
/// key files hold PKCS #8 ("BEGIN PRIVATE KEY").
enum PEM {
    static let rsaEncryptionOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    static func rsaPrivateKey(_ pem: String) throws -> Data {
        let isPKCS1 = pem.contains("BEGIN RSA PRIVATE KEY")
        let body = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .replacingOccurrences(of: "\\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let der = Data(base64Encoded: body) else { throw SpendError.invalidKey }
        return isPKCS1 ? der : try pkcs1(fromPKCS8: der)
    }

    /// PrivateKeyInfo ::= SEQUENCE { version INTEGER, algorithm SEQUENCE { OID, NULL }, privateKey OCTET STRING }
    static func pkcs1(fromPKCS8 der: Data) throws -> Data {
        var outer = DERReader(Array(der))
        var info = DERReader(try outer.read(tag: 0x30))
        _ = try info.read(tag: 0x02)
        var algorithm = DERReader(try info.read(tag: 0x30))
        guard try algorithm.read(tag: 0x06) == rsaEncryptionOID else { throw SpendError.invalidKey }
        return Data(try info.read(tag: 0x04))
    }
}

struct DERReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Reads one element with the expected tag and returns its contents.
    mutating func read(tag: UInt8) throws -> [UInt8] {
        guard index < bytes.count, bytes[index] == tag else { throw SpendError.invalidKey }
        index += 1
        guard index < bytes.count else { throw SpendError.invalidKey }
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let lengthBytes = length & 0x7F
            guard lengthBytes > 0, lengthBytes <= 4, index + lengthBytes <= bytes.count else { throw SpendError.invalidKey }
            length = 0
            for _ in 0..<lengthBytes {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard length >= 0, index + length <= bytes.count else { throw SpendError.invalidKey }
        defer { index += length }
        return Array(bytes[index..<(index + length)])
    }
}

/// Exchanges a service account key for short-lived access tokens, and keeps each until a minute before it
/// expires. Tokens live only in memory.
final class GoogleTokenSource: @unchecked Sendable {
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    private let http: HTTPClient
    private let signer: RS256Signer
    private let lock = NSLock()
    private var cache: [String: (token: String, expires: Date)] = [:]

    init(http: HTTPClient, signer: RS256Signer) {
        self.http = http
        self.signer = signer
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The unsigned JWT, "header.claims". Keys are sorted so the output is stable for tests.
    static func unsignedJWT(_ account: GoogleServiceAccount, scope: String, now: Date) throws -> String {
        var header = ["alg": "RS256", "typ": "JWT"]
        if let kid = account.privateKeyID { header["kid"] = kid }
        let issued = Int(now.timeIntervalSince1970)
        let claims: [String: Any] = [
            "iss": account.clientEmail, "scope": scope, "aud": tokenURL.absoluteString,
            "iat": issued, "exp": issued + 3600
        ]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let claimsData = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        return base64URL(headerData) + "." + base64URL(claimsData)
    }

    func token(for account: GoogleServiceAccount, scope: String, now: Date) async throws -> String {
        let key = account.clientEmail + " " + scope
        if let cached = lock.withLock({ cache[key] }), cached.expires > now.addingTimeInterval(60) {
            return cached.token
        }
        let unsigned = try Self.unsignedJWT(account, scope: scope, now: now)
        let signature = try signer.sign(Data(unsigned.utf8), privateKeyPEM: account.privateKey)
        let assertion = unsigned + "." + Self.base64URL(signature)
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: assertion)
        ]
        let request = HTTPRequest(method: .post, url: Self.tokenURL,
                                  headers: ["Content-Type": "application/x-www-form-urlencoded",
                                            "accept": "application/json"],
                                  body: Data((form.percentEncodedQuery ?? "").utf8))
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch let error as SpendError {
            throw error
        } catch {
            throw SpendError.network
        }
        switch response.status {
        case 200..<300: break
        // invalid_grant: a deleted or disabled key, or a clock that's far off.
        case 400, 401, 403: throw SpendError.invalidKey
        default: throw SpendError.from(status: response.status, headers: response.headers, missingScopeHint: "")
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: response.body) else {
            throw SpendError.unexpectedResponse
        }
        let expires = now.addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
        lock.withLock { cache[key] = (decoded.accessToken, expires) }
        return decoded.accessToken
    }
}
