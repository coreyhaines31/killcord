import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A request, as plain values so adapters can be tested without a network.
public struct HTTPRequest: Sendable, Equatable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    /// Stricter limits for requests to an address the person typed in (custom connections): no redirect to
    /// another host or scheme, a smaller response, and a shorter wait. Nil for the built-in providers.
    public var limits: Limits?

    public struct Limits: Sendable, Equatable {
        public var maxResponseBytes: Int
        public var timeout: TimeInterval

        public init(maxResponseBytes: Int, timeout: TimeInterval) {
            self.maxResponseBytes = maxResponseBytes
            self.timeout = timeout
        }
    }

    public init(method: Method = .get, url: URL, headers: [String: String] = [:], body: Data? = nil,
                limits: Limits? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.limits = limits
    }

    /// A query parameter's values, in order. For tests.
    public func query(_ name: String) -> [String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .filter { $0.name == name }.compactMap(\.value) ?? []
    }

    public var path: String { url.path }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    /// Header names lowercased.
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }) { $1 }
        self.body = body
    }

    public init(status: Int, json: String, headers: [String: String] = [:]) {
        self.init(status: status, headers: headers.merging(["content-type": "application/json"]) { $1 },
                  body: Data(json.utf8))
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

/// The one way adapters reach the network. Injected so every adapter can be tested with `MockHTTPClient`.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    /// The IP addresses a host name resolves to, or nil when it doesn't resolve. Custom connections check
    /// them before sending anything.
    func addresses(for host: String) async -> [String]?
}

extension HTTPClient {
    public func addresses(for host: String) async -> [String]? {
        HostSafety.resolve(host)
    }
}

/// The real client: an ephemeral session, so nothing (cookies, cached responses with spend in them) is
/// written to disk.
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.setValue("\(Brand.name) (macOS menu bar app)", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            if let limits = request.limits {
                urlRequest.timeoutInterval = limits.timeout
                (data, response) = try await limited(urlRequest, limits)
            } else {
                (data, response) = try await session.data(for: urlRequest)
            }
        } catch let error as SpendError {
            throw error
        } catch let error as URLError {
            throw SpendError(urlError: error)
        } catch {
            throw SpendError.network
        }
        guard let http = response as? HTTPURLResponse else { throw SpendError.network }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }

    /// Reads at most `maxResponseBytes`, and refuses a redirect to another host or scheme before it's followed,
    /// so a key is never sent somewhere the person didn't type.
    private func limited(_ request: URLRequest, _ limits: HTTPRequest.Limits) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        // Custom connections are a macOS feature; the Linux build only runs the core tests, on mocks.
        throw SpendError.network
        #else
        // The request's timeout only covers silence; a reply that trickles in also has a whole-request deadline.
        let deadline = Date().addingTimeInterval(limits.timeout * 2)
        let (bytes, response) = try await session.bytes(for: request, delegate: SameHostRedirects())
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limits.maxResponseBytes { throw SpendError.unexpectedResponse }
            if Date() > deadline { throw SpendError.network }
        }
        guard Date() <= deadline else { throw SpendError.network }
        return (data, response)
        #endif
    }
}

#if !canImport(FoundationNetworking)
/// Follows a redirect only when it stays on the same scheme, host and port.
final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let origin = task.originalRequest?.url, let target = request.url else { return nil }
        return Self.allows(from: origin, to: target) ? request : nil
    }

    static func allows(from origin: URL, to target: URL) -> Bool {
        origin.scheme?.lowercased() == target.scheme?.lowercased()
            && origin.host?.lowercased() == target.host?.lowercased() && origin.port == target.port
    }
}
#endif

/// A scripted client for tests and demo mode. Records every request; answers with a handler.
public final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) throws -> HTTPResponse

    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [HTTPRequest] = []

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Answers by URL path: the first entry whose key the request's path ends with.
    public convenience init(routes: [String: HTTPResponse]) {
        self.init { request in
            let match = routes.filter { request.url.path.hasSuffix($0.key) }.max { $0.key.count < $1.key.count }
            return match?.value ?? HTTPResponse(status: 404, json: #"{"error":"no route"}"#)
        }
    }

    public var requests: [HTTPRequest] {
        lock.withLock { recorded }
    }

    public func setHandler(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let handler = lock.withLock {
            recorded.append(request)
            return self.handler
        }
        return try handler(request)
    }

    /// Host to addresses, for custom connections. Every host resolves to one public address unless a test
    /// says otherwise; nothing is looked up.
    public var resolver: @Sendable (String) -> [String]? = { _ in ["93.184.215.14"] }

    public func addresses(for host: String) async -> [String]? {
        resolver(host)
    }
}

extension URL {
    /// A URL with query items appended, for building requests.
    func adding(_ items: [URLQueryItem]) -> URL {
        guard !items.isEmpty, var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.queryItems = (components.queryItems ?? []) + items
        // `+` in a value must reach the server as a plus sign, not a space (RFC 3339 offsets, cursors).
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? self
    }
}
