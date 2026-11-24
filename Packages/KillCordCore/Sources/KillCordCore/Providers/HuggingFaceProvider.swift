// Hugging Face Inference Providers spend for an organization, today and this month. Enterprise plans and above only.
// Reference: https://huggingface.co/docs/inference-providers/pricing ("Retrieve organization usage via the API";
// "This feature is part of the Enterprise plan and above"). Schema: https://huggingface.co/.well-known/openapi.json
//
// GET https://huggingface.co/api/organizations/{org}/billing/usage/inference?startDate=…Z&endDate=…Z&limit=31
//   headers: Authorization: Bearer <token with permission to read the organization's billing>
//   200:     [{ "period": "2026-11-14T00:00:00.000Z", "usage": [{ "user": "…", "model": "…", "provider": "…",
//               "requestCount": 3, "costCents": 12, "inputTokens": …, "outputTokens": …, "cachedInputTokens": … }] }]
// One entry per day; `limit` is days per page (up to 31), with a `Link: <…>; rel="next"` header for more. Costs are
// in cents, "rounded to the nearest cent for each row". Requests appear "up to 2 hours after they are made".
import Foundation

public struct HuggingFaceProvider: SpendProvider {
    public let id = ProviderID.huggingface
    static let host = "huggingface.co"
    static let maxPages = 3

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Give the token permission to read the organization's "
            + "billing. Usage over the API needs an Enterprise plan or above.")
    }

    struct Day: Decodable {
        let period: String
        let usage: [Row]

        struct Row: Decodable {
            let costCents: FlexibleDecimal
        }
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let token = try credentials.require("apiKey")
        let organization = try credentials.require("organization")
        // It goes into the path, so only the characters an organization name can have.
        guard FieldFormat.isIdentifier(organization.replacingOccurrences(of: ".", with: "-")) else {
            throw SpendError.requiresSetup("the organization name doesn't look right. Use the name in its "
                + "huggingface.co address.")
        }
        let window = window(now)
        var url: URL? = URL(string: "https://\(Self.host)/api/organizations/\(organization)/billing/usage/inference")!
            .adding([URLQueryItem(name: "startDate", value: ISO8601.string(window.monthStart)),
                     URLQueryItem(name: "endDate", value: ISO8601.string(now)),
                     URLQueryItem(name: "limit", value: "31")])
        var monthCents = Decimal(0)
        var todayCents = Decimal(0)
        var pages = 0
        while let next = url, pages < Self.maxPages {
            pages += 1
            let response = try await api.send(HTTPRequest(url: next, headers: ["Authorization": "Bearer \(token)"]))
            for day in try api.decode([Day].self, from: response) {
                let cents = day.usage.reduce(Decimal(0)) { $0 + $1.costCents.value }
                monthCents += cents
                if day.period.prefix(10) == window.dayKey { todayCents += cents }
            }
            url = Self.nextLink(response.header("link"))
        }
        if url != nil { throw SpendError.unexpectedResponse }
        return SpendSnapshot(provider: id, today: Money(todayCents / 100), month: Money(monthCents / 100),
                             fetchedAt: now)
    }

    /// The `rel="next"` address from a Link header, only when it stays on huggingface.co over https.
    static func nextLink(_ header: String?) -> URL? {
        guard let header else { return nil }
        for part in header.split(separator: ",") where part.contains("rel=\"next\"") {
            guard let start = part.firstIndex(of: "<"), let end = part.firstIndex(of: ">"), start < end,
                  let url = URL(string: String(part[part.index(after: start)..<end])),
                  url.scheme == "https", url.host == host else { return nil }
            return url
        }
        return nil
    }
}
