import Foundation

/// A connection the person sets up for a service Kill Cord doesn't know: an https address, how to send
/// the key, and where in the JSON reply the balance is. Every field, the address included, is saved in the
/// Keychain with the key, like any other connection. Kill Cord can't check that the numbers are right.
public struct CustomConfig: Sendable, Equatable {
    public enum AuthStyle: String, Sendable, CaseIterable {
        case header = "Header"
        case query = "Query parameter"
        case basic = "Basic"
        case none = "None"
    }

    public enum Scale: String, Sendable, CaseIterable {
        case asSent = "As sent"
        case cents = "Cents"
        case millionths = "Millionths"

        var divisor: Decimal {
            switch self {
            case .asSent: 1
            case .cents: 100
            case .millionths: 1_000_000
            }
        }
    }

    public static let kinds = ["Prepaid balance", "Allowance that resets"]
    public static let pollChoices = ["15", "30", "60", "240", "1440"]
    /// Kill Cord never checks a custom service more often than this.
    public static let minimumInterval: TimeInterval = 15 * 60
    /// When each check costs money, at most hourly.
    public static let paidCheckInterval: TimeInterval = 60 * 60
    public static let limits = HTTPRequest.Limits(maxResponseBytes: 256 * 1024, timeout: 15)

    public let url: URL
    public let method: HTTPRequest.Method
    public let auth: AuthStyle
    public let authName: String
    public let authValue: String
    public let key: String?
    public let secondKey: String?
    public let body: Data?
    public let remaining: JSONPath?
    public let used: JSONPath?
    public let limit: JSONPath?
    public let reset: JSONPath?
    public let currency: JSONPath?
    public let unit: Balance.Unit
    public let scale: Scale
    public let dollarsPerUnit: Decimal?
    public let kind: Balance.Kind
    public let interval: TimeInterval
    public let checksCostMoney: Bool

    /// Reads and checks the saved fields. Throws `.requiresSetup` with what to fix, in words.
    public init(_ credentials: ProviderCredentials) throws {
        url = try Self.address(credentials)
        method = credentials["method"] == "POST" ? .post : .get
        key = credentials["key"]
        secondKey = credentials["key2"]
        let setting = try Self.auth(credentials)
        (auth, authName, authValue) = (setting.style, setting.name, setting.value)
        body = try Self.body(credentials, method: method)
        remaining = try Self.path(credentials, "remainingPath")
        used = try Self.path(credentials, "usedPath")
        limit = try Self.path(credentials, "limitPath")
        reset = try Self.path(credentials, "resetPath")
        currency = try Self.path(credentials, "currencyPath")
        if remaining == nil, (used == nil) != (limit == nil) {
            throw Self.fix("to work out what's left, fill in both the used and limit paths.")
        }
        unit = try Self.unit(credentials)
        scale = Scale(rawValue: credentials["scale"] ?? "") ?? .asSent
        dollarsPerUnit = try Self.rate(credentials)
        kind = credentials["kind"] == Self.kinds[1] ? .allowance : .prepaid
        checksCostMoney = credentials["costsMoney"] == "Yes"
        let minutes = TimeInterval(credentials["pollMinutes"] ?? "") ?? 15
        interval = max(minutes * 60, checksCostMoney ? Self.paidCheckInterval : Self.minimumInterval)
    }

    /// "{key}" and "{key2}" replaced.
    static func fill(_ template: String, key: String?, secondKey: String?) -> String {
        template.replacingOccurrences(of: "{key}", with: key ?? "").replacingOccurrences(of: "{key2}", with: secondKey ?? "")
    }

    static func isToken(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil
    }

    /// The request, with the key where the auth style puts it.
    public func request() -> HTTPRequest {
        var target = url
        var headers: [String: String] = ["Accept": "application/json"]
        switch auth {
        case .header:
            headers[authName] = Self.fill(authValue, key: key, secondKey: secondKey)
        case .query:
            target = url.adding([URLQueryItem(name: authName, value: key)])
        case .basic:
            let pair = "\(key ?? ""):\(secondKey ?? "")"
            headers["Authorization"] = "Basic " + Data(pair.utf8).base64EncodedString()
        case .none:
            break
        }
        if body != nil { headers["Content-Type"] = "application/json" }
        return HTTPRequest(method: method, url: target, headers: headers, body: body, limits: Self.limits)
    }

    /// Every secret this connection could put in a request, for removing from error text.
    public var secrets: [String] {
        var values = [key, secondKey].compactMap { $0 }
        if auth == .header { values.append(Self.fill(authValue, key: key, secondKey: secondKey)) }
        if auth == .basic { values.append(Data("\(key ?? ""):\(secondKey ?? "")".utf8).base64EncodedString()) }
        return values.filter { $0.count >= 4 }
    }

    /// The balance in a response body.
    public func balance(from data: Data) throws -> Balance {
        let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var remainingValue: Decimal?
        var usedValue = used.flatMap { path in root.flatMap(path.decimal) }
        var limitValue = limit.flatMap { path in root.flatMap(path.decimal) }
        if let remaining {
            remainingValue = root.flatMap(remaining.decimal)
        } else if let usedValue, let limitValue {
            remainingValue = limitValue - usedValue
        } else if used == nil, limit == nil {
            // The whole reply is the number ("1234.5").
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            remainingValue = JSONPath.decimal(root) ?? Money.decimal(text)
        }
        guard var remainingValue else { throw SpendError.unexpectedResponse }
        remainingValue /= scale.divisor
        usedValue = usedValue.map { $0 / scale.divisor }
        limitValue = limitValue.map { $0 / scale.divisor }
        var unit = unit
        if let currency, let code = root.flatMap(currency.value) as? String {
            guard code.range(of: "^[A-Za-z]{3}$", options: .regularExpression) != nil else {
                throw SpendError.unexpectedResponse
            }
            unit = .money(Currency(code))
        }
        return Balance(remaining: remainingValue, unit: unit, kind: kind, limit: limitValue, used: usedValue,
                       dollarsPerUnit: unit == .money(.usd) ? nil : dollarsPerUnit,
                       resetsAt: reset.flatMap { path in root.flatMap(path.date) })
    }
}

/// Checking each saved field, one at a time.
extension CustomConfig {
    static func fix(_ what: String) -> SpendError { .requiresSetup(what) }

    /// The id of the first field the setup can't use, or nil when it's all readable. Settings opens the
    /// Advanced fields when the problem is in one of them.
    public static func fieldWithProblem(_ credentials: ProviderCredentials) -> String? {
        let checks: [(String, () throws -> Void)] = [
            ("url", { _ = try address(credentials) }),
            (authField(credentials), { _ = try auth(credentials) }),
            ("body", { _ = try body(credentials, method: credentials["method"] == "POST" ? .post : .get) }),
            ("remainingPath", { _ = try path(credentials, "remainingPath") }),
            ("usedPath", { _ = try path(credentials, "usedPath") }),
            ("limitPath", { _ = try path(credentials, "limitPath") }),
            ("resetPath", { _ = try path(credentials, "resetPath") }),
            ("currencyPath", { _ = try path(credentials, "currencyPath") }),
            ("unit", { _ = try unit(credentials) }),
            ("dollarsPerUnit", { _ = try rate(credentials) })
        ]
        for (field, check) in checks where (try? check()) == nil { return field }
        if credentials["remainingPath"] == nil, (credentials["usedPath"] == nil) != (credentials["limitPath"] == nil) {
            return credentials["usedPath"] == nil ? "usedPath" : "limitPath"
        }
        return nil
    }

    static func address(_ credentials: ProviderCredentials) throws -> URL {
        guard let text = credentials["url"], let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else {
            throw fix("the address has to start with https://.")
        }
        guard url.user == nil, url.password == nil else { throw fix("put the key in its own field, not in the address.") }
        return url
    }

    /// The auth style with its header or parameter name and value template.
    struct AuthSetting {
        let style: AuthStyle
        let name: String
        let value: String
    }

    static func auth(_ credentials: ProviderCredentials) throws -> AuthSetting {
        let style = AuthStyle(rawValue: credentials["authStyle"] ?? "") ?? .header
        let key = credentials["key"]
        switch style {
        case .header:
            return try headerAuth(credentials)
        case .query:
            let name = credentials["authName"] ?? "api_key"
            guard isToken(name) else { throw fix("the parameter name can only use letters, digits and - _.") }
            guard key != nil else { throw fix("fill in the key.") }
            return AuthSetting(style: style, name: name, value: "")
        case .basic:
            guard let key else { throw fix("fill in the Basic user name or key.") }
            guard !key.contains(":") else { throw fix("a Basic user name can't contain a colon.") }
            return AuthSetting(style: style, name: "", value: "")
        case .none:
            return AuthSetting(style: style, name: "", value: "")
        }
    }

    /// Which auth field a refusal is about: a bad name, a header value over two lines, or else the key.
    static func authField(_ credentials: ProviderCredentials) -> String {
        if let name = credentials["authName"], !isToken(name) { return "authName" }
        if credentials["authValue"]?.contains(where: \.isNewline) == true { return "authValue" }
        return "key"
    }

    static func headerAuth(_ credentials: ProviderCredentials) throws -> AuthSetting {
        let name = credentials["authName"] ?? "Authorization"
        let value = credentials["authValue"] ?? "Bearer {key}"
        guard isToken(name) else { throw fix("the header name can only use letters, digits and - _.") }
        guard !value.contains(where: \.isNewline) else { throw fix("the header value can't span lines.") }
        if value.contains("{key}"), credentials["key"] == nil { throw fix("fill in the key.") }
        return AuthSetting(style: .header, name: name, value: value)
    }

    static func body(_ credentials: ProviderCredentials, method: HTTPRequest.Method) throws -> Data? {
        guard let raw = credentials["body"] else { return nil }
        guard method == .post else { throw fix("a JSON body needs POST.") }
        let filled = Data(fill(raw, key: credentials["key"], secondKey: credentials["key2"]).utf8)
        guard (try? JSONSerialization.jsonObject(with: filled)) != nil else { throw fix("the body isn't valid JSON.") }
        return filled
    }

    static func path(_ credentials: ProviderCredentials, _ id: String) throws -> JSONPath? {
        guard let text = credentials[id] else { return nil }
        guard let path = JSONPath(text) else { throw fix("\"\(text)\" isn't a path Kill Cord can follow.") }
        return path
    }

    static func unit(_ credentials: ProviderCredentials) throws -> Balance.Unit {
        let text = credentials["unit"] ?? "USD"
        if text.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil { return .money(Currency(text)) }
        guard text.count <= 30 else { throw fix("keep the unit to a word or two, like credits.") }
        return .units(text)
    }

    static func rate(_ credentials: ProviderCredentials) throws -> Decimal? {
        guard let text = credentials["dollarsPerUnit"] else { return nil }
        guard let value = Money.decimal(text), value > 0 else { throw fix("dollars per unit has to be a number.") }
        return value
    }
}

extension ProviderInfo {
    static let customFields: [CredentialField] = [
        CredentialField(id: "serviceName", label: "Service name", placeholder: "ScrapeCreators", isSecret: false,
                        help: "What Kill Cord calls it."),
        CredentialField(id: "url", label: "Balance address", placeholder: "https://api.example.com/v1/balance",
                        isSecret: false, help: "https only. Kill Cord won't follow a redirect to another host, and "
                            + "won't call an address on your own network."),
        CredentialField(id: "method", label: "Method", isSecret: false, choices: ["GET", "POST"],
                        isAdvanced: true),
        CredentialField(id: "authStyle", label: "Send the key as", isSecret: false,
                        choices: CustomConfig.AuthStyle.allCases.map(\.rawValue)),
        CredentialField(id: "authName", label: "Header or parameter name", placeholder: "Authorization",
                        isSecret: false, isOptional: true,
                        help: "For a header: Authorization, x-api-key. For a query parameter: api_key.",
                        isAdvanced: true),
        CredentialField(id: "authValue", label: "Header value", placeholder: "Bearer {key}", isSecret: false,
                        isOptional: true, help: "{key} becomes the key above. Empty means Bearer {key}.",
                        isAdvanced: true),
        CredentialField(id: "key", label: "Key", placeholder: "API key", isSecret: true, isOptional: true,
                        help: "For Basic, the user name or key."),
        CredentialField(id: "key2", label: "Second secret", placeholder: "Basic password", isSecret: true,
                        isOptional: true, help: "Only for Basic: the password. Usable as {key2}.",
                        isAdvanced: true),
        CredentialField(id: "body", label: "JSON body", placeholder: "{ }", isSecret: false, isOptional: true,
                        isMultiline: true, help: "Only for POST. Sent as application/json.",
                        isAdvanced: true),
        CredentialField(id: "remainingPath", label: "Path to what's left", placeholder: "data.balance",
                        isSecret: false, isOptional: true,
                        help: "Keys and numbers with dots: data.items.0.credits. Leave empty if the whole reply "
                            + "is a number, or to work it out from used and limit under Advanced."),
        CredentialField(id: "usedPath", label: "Path to used", placeholder: "data.used", isSecret: false,
                        isOptional: true,
                        isAdvanced: true),
        CredentialField(id: "limitPath", label: "Path to limit", placeholder: "data.limit", isSecret: false,
                        isOptional: true,
                        isAdvanced: true),
        CredentialField(id: "resetPath", label: "Path to reset date", placeholder: "data.resets_at", isSecret: false,
                        isOptional: true, help: "An ISO date, 2026-12-01, or Unix seconds.",
                        isAdvanced: true),
        CredentialField(id: "currencyPath", label: "Path to currency code", placeholder: "data.currency",
                        isSecret: false, isOptional: true,
                        isAdvanced: true),
        CredentialField(id: "unit", label: "Unit", placeholder: "USD", isSecret: false, isOptional: true,
                        help: "A currency code like USD for money, or the word for what it counts, like credits.",
                        isAdvanced: true),
        CredentialField(id: "scale", label: "Amounts are in", isSecret: false,
                        help: "Cents divides by 100. Millionths divides by 1,000,000 (micro-dollars).",
                        choices: CustomConfig.Scale.allCases.map(\.rawValue),
                        isAdvanced: true),
        CredentialField(id: "dollarsPerUnit", label: "Dollars per unit", placeholder: "0.01", isSecret: false,
                        isOptional: true, help: "For units that aren't money. Shown only as a labeled estimate.",
                        isAdvanced: true),
        CredentialField(id: "kind", label: "Kind", isSecret: false, choices: CustomConfig.kinds),
        CredentialField(id: "pollMinutes", label: "Check at most every (minutes)", isSecret: false,
                        choices: CustomConfig.pollChoices,
                        isAdvanced: true),
        CredentialField(id: "costsMoney", label: "Each check costs money", isSecret: false,
                        help: "If yes, Kill Cord checks at most once an hour.", choices: ["No", "Yes"],
                        isAdvanced: true)
    ]

    static let custom = ProviderInfo(
        id: .custom, name: "Custom service", capability: .balance(spend: []),
        fields: customFields,
        keyKind: "key for that service",
        keyURL: nil,
        keyPowerWarning: "Kill Cord can't know what a custom service's key can do. Use the most limited key the "
            + "service offers. Kill Cord sends it only to the address you enter, over https.",
        lag: ProviderLag(typical: 0, note: "Numbers come from your own setup. Kill Cord can't check that they're "
            + "right."),
        billingTimeZone: utc, minimumRefreshInterval: CustomConfig.minimumInterval,
        consoleURL: url("https://killcord.app/")
    )
}
