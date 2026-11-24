import Foundation

/// One provider's spend, as read at one moment.
public struct SpendSnapshot: Sendable, Equatable, Codable {
    public enum MonthKind: Sendable, Equatable, Codable {
        /// The calendar month in the provider's billing time zone.
        case calendarMonth
        /// The provider's own billing period, which may start mid-month (Cloudflare).
        case billingPeriod(start: Date)
    }

    public let provider: ProviderID
    /// Spend so far today. Nil when the provider hasn't reported today yet: not the same as $0.
    public var today: Money?
    /// Spend so far this month (or billing period). Nil when the provider reports no money.
    public var month: Money?
    public var monthKind: MonthKind
    /// Usage in the provider's units, for providers that don't report money (Neon).
    public var usage: [UsageMetric]
    /// What's left of a prepaid balance or plan allowance. Not spend: never added into totals.
    public var balance: Balance?
    /// A plan the person typed in, for services with no API. Not live, and never added into totals.
    public var manual: ManualPlan?
    /// True when the numbers are worked out by Kill Cord rather than reported by the provider.
    public var isEstimate: Bool
    /// The provider's own "current through" time, when it says.
    public var dataAsOf: Date?
    /// When Kill Cord read it.
    public var fetchedAt: Date

    public init(provider: ProviderID, today: Money?, month: Money?, monthKind: MonthKind = .calendarMonth,
                usage: [UsageMetric] = [], balance: Balance? = nil, manual: ManualPlan? = nil, isEstimate: Bool = false,
                dataAsOf: Date? = nil, fetchedAt: Date) {
        self.provider = provider
        self.today = today
        self.month = month
        self.monthKind = monthKind
        self.usage = usage
        self.balance = balance
        self.manual = manual
        self.isEstimate = isEstimate
        self.dataAsOf = dataAsOf
        self.fetchedAt = fetchedAt
    }
}

/// An amount of something that isn't money: "1,234 CU-hours".
public struct UsageMetric: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let value: Decimal
    public let unit: String

    public init(id: String, name: String, value: Decimal, unit: String) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
    }
}

/// "Today" and "this month" on a provider's billing clock.
public struct BillingWindow: Sendable, Equatable {
    public let now: Date
    public let timeZone: TimeZone
    public let dayStart: Date
    public let monthStart: Date
    /// "2026-11-15"
    public let dayKey: String
    /// "2026-11"
    public let monthKey: String

    public init(now: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.now = now
        self.timeZone = timeZone
        dayStart = calendar.startOfDay(for: now)
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        monthStart = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1))!
        dayKey = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        monthKey = String(format: "%04d-%02d", parts.year!, parts.month!)
    }

    /// The start of tomorrow, the exclusive end for "today".
    public var dayEnd: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: 1, to: dayStart)!
    }
}

/// What an API said about a native cap, for providers that let Kill Cord check.
public struct CapVerification: Sendable, Equatable, Codable {
    public enum Status: Sendable, Equatable, Codable {
        /// The provider says the cap is set. The detail says how ("Hard limit at $500 a month").
        case on(String)
        /// The provider says there's no such cap.
        case off(String)
        /// The cap is set and has been hit: usage is stopped now.
        case enforced(String)
    }

    public let capID: String
    public let status: Status
    public let checkedAt: Date

    public init(capID: String, status: Status, checkedAt: Date) {
        self.capID = capID
        self.status = status
        self.checkedAt = checkedAt
    }
}

/// An adapter for one provider's official billing API. Pure apart from `HTTPClient`, so each can be
/// tested with recorded responses.
public protocol SpendProvider: Sendable {
    var id: ProviderID { get }
    /// A cheap call that proves the key works and can read billing. Throws `SpendError`.
    func validate(_ credentials: ProviderCredentials, now: Date) async throws
    /// Today and this month. Throws `SpendError`.
    func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot
    /// Caps the API can confirm. Empty when it can't confirm any; failures are skipped, not thrown, since
    /// the audit falls back to what the person marked.
    func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification]
}

extension SpendProvider {
    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] { [] }

    public func window(_ now: Date) -> BillingWindow {
        BillingWindow(now: now, timeZone: id.info.billingTimeZone)
    }
}

public enum SpendProviders {
    // One case per provider.
    // swiftlint:disable:next cyclomatic_complexity
    public static func make(_ id: ProviderID, http: HTTPClient) -> SpendProvider {
        switch id {
        case .anthropic: AnthropicProvider(http: http)
        case .google: GoogleCloudProvider(http: http)
        case .openai: OpenAIProvider(http: http)
        case .vercel: VercelProvider(http: http)
        case .cloudflare: CloudflareProvider(http: http)
        case .twilio: TwilioProvider(http: http)
        case .neon: NeonProvider(http: http)
        case .supabase: SupabaseProvider()
        case .runpod: RunpodProvider(http: http)
        case .deepinfra: DeepInfraProvider(http: http)
        case .xapi: XAPIProvider(http: http)
        case .bfl: BFLProvider(http: http)
        case .digitalocean: DigitalOceanProvider(http: http)
        case .telnyx: TelnyxProvider(http: http)
        case .openrouter: OpenRouterProvider(http: http)
        case .dataforseo: DataForSEOProvider(http: http)
        case .ahrefs: AhrefsProvider(http: http)
        case .firecrawl: FirecrawlProvider(http: http)
        case .treg: TregProvider(http: http)
        case .monid: MonidProvider(http: http)
        case .fal: FalProvider(http: http)
        case .elevenlabs: ElevenLabsProvider(http: http)
        case .xai: XAIProvider(http: http)
        case .deepseek: DeepSeekProvider(http: http)
        case .apify: ApifyProvider(http: http)
        case .tavily: TavilyProvider(http: http)
        case .deepgram: DeepgramProvider(http: http)
        case .runway: RunwayProvider(http: http)
        case .serpapi: SerpApiProvider(http: http)
        case .brightdata: BrightDataProvider(http: http)
        case .scrapecreators: ScrapeCreatorsProvider(http: http)
        case .stability: StabilityProvider(http: http)
        case .moonshot: KimiProvider(http: http)
        case .custom: CustomProvider(http: http)
        case .manual: ManualProvider()
        }
    }
}

/// Shared plumbing for adapters: send, map HTTP failures to `SpendError`, decode.
struct APIRequester: Sendable {
    let http: HTTPClient
    let missingScopeHint: String

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch let error as SpendError {
            throw error
        } catch {
            throw SpendError.network
        }
        guard (200..<300).contains(response.status) else {
            throw SpendError.from(status: response.status, headers: response.headers,
                                  missingScopeHint: missingScopeHint,
                                  detail: ProviderErrorDetail.message(in: response.body, sentWith: request))
        }
        return response
    }

    func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw SpendError.unexpectedResponse
        }
    }

    func get<T: Decodable>(_ type: T.Type, _ url: URL, headers: [String: String]) async throws -> T {
        try decode(type, from: try await send(HTTPRequest(url: url, headers: headers)))
    }
}

/// The human sentence in a provider's error body, for 4xx failures. Handles the common shapes:
/// `{error: {message}}` (Anthropic, OpenAI, Vercel), `{errors: [{message}]}` (Cloudflare), and
/// `{message}` (Neon, Twilio). Every header value the request carried (keys and tokens travel only in
/// headers) is removed first, so a provider echoing the key back can't put it on screen.
enum ProviderErrorDetail {
    static let maxLength = 200

    static func message(in body: Data, sentWith request: HTTPRequest, alsoRemoving extra: [String] = []) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let raw = text(in: object) else { return nil }
        var message = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let values = (sensitiveValues(in: request) + extra.filter { !$0.isEmpty }).sorted { $0.count > $1.count }
        for value in values {
            message = message.replacingOccurrences(of: value, with: "[redacted]")
        }
        guard !message.isEmpty else { return nil }
        return message.count > maxLength ? String(message.prefix(maxLength - 1)) + "…" : message
    }

    private static func text(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        // `{errors: [{title, detail}]}` is the JSON:API shape (Telnyx).
        if let errors = object["errors"] as? [[String: Any]], let first = errors.first,
           let message = first["message"] as? String ?? first["detail"] as? String ?? first["title"] as? String {
            return message
        }
        if let message = object["message"] as? String { return message }
        if let message = object["error"] as? String { return message }
        // `{detail: "…"}`, `{detail: {message | error}}` and `{detail: [{msg}]}` (ElevenLabs, Tavily), and
        // Deepgram's older `{err_msg}`.
        if let detail = object["detail"] as? String { return detail }
        if let detail = object["detail"] as? [String: Any] {
            return detail["message"] as? String ?? detail["error"] as? String
        }
        if let details = object["detail"] as? [[String: Any]], let message = details.first?["msg"] as? String {
            return message
        }
        return object["err_msg"] as? String
    }

    private static let plainHeaders: Set<String> = ["accept", "content-type", "anthropic-version", "user-agent",
                                                           "x-runway-version"]

    /// Header values, whole and split on spaces ("Bearer abc" gives "abc"), plus what a Basic auth token
    /// decodes to ("sid:token" gives both halves), and query values (SerpApi takes its key as `api_key=`).
    /// Longest first.
    private static func sensitiveValues(in request: HTTPRequest) -> [String] {
        var values: Set<String> = []
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in query {
            if let value = item.value { values.insert(value) }
        }
        for (name, value) in request.headers where !plainHeaders.contains(name.lowercased()) {
            values.insert(value)
            for word in value.split(separator: " ").map(String.init) {
                values.insert(word)
                guard let data = Data(base64Encoded: word), let decoded = String(data: data, encoding: .utf8) else {
                    continue
                }
                values.insert(decoded)
                for part in decoded.split(separator: ":") { values.insert(String(part)) }
            }
        }
        return values.filter { $0.count >= 8 }.sorted { $0.count > $1.count }
    }
}

enum ISO8601 {
    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// "2026-11-15" in a time zone.
    static func day(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
