// A service the person set up themselves (`CustomConfig`). One request to the address they typed, with
// stricter limits than the built-in providers: https only, a public address checked before sending, no
// redirect to another host, at most 256 KB back, 15 seconds. Errors carry the service's own message with
// every secret of this connection removed.
import Foundation

public struct CustomProvider: SpendProvider {
    public let id = ProviderID.custom
    private let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let config = try CustomConfig(credentials)
        let request = config.request()
        let host = request.url.host ?? ""
        let addresses = HostSafety.isIPLiteral(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
            ? nil : await http.addresses(for: host)
        if let problem = HostSafety.problem(host: host, addresses: addresses) {
            throw SpendError.requiresSetup(problem)
        }
        if addresses == nil, !HostSafety.isIPLiteral(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))) {
            throw SpendError.network
        }
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch let error as SpendError {
            throw error
        } catch {
            throw SpendError.network
        }
        guard response.body.count <= CustomConfig.limits.maxResponseBytes else { throw SpendError.unexpectedResponse }
        guard (200..<300).contains(response.status) else {
            throw SpendError.from(status: response.status, headers: response.headers,
                                  missingScopeHint: "Check that the key can read this address.",
                                  detail: ProviderErrorDetail.message(in: response.body, sentWith: request,
                                                                      alsoRemoving: config.secrets))
        }
        return SpendSnapshot(provider: id, today: nil, month: nil, balance: try config.balance(from: response.body),
                             fetchedAt: now)
    }
}
