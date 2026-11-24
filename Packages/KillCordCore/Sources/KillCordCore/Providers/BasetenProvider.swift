// Baseten spend today and this month.
// Reference: https://docs.baseten.co/reference/management-api/billing/gets-billing-usage-summary-for-a-date-range
// Keys: https://docs.baseten.co/organization/api-keys
//
// GET https://api.baseten.co/v1/billing/usage_summary?start_date=<ISO 8601>&end_date=<ISO 8601>
//   headers: Authorization: Bearer <API key>
//   200:     { "dedicated_usage": { "subtotal": 12.5, "credits_used": 0, "total": 12.5, "minutes": 90, … },
//              "training_usage": { … }, "model_apis_usage": { … }, "loops_usage": { … } }   (each may be null)
// "Returns billing usage within [start_date, end_date) … Both dates are normalized to midnight UTC … Usage
// subtotals are before credits … The date range must not exceed 31 days." Amounts are numbers or decimal
// strings, in dollars. Kill Cord adds up each product's `total` (after credits).
import Foundation

public struct BasetenProvider: SpendProvider {
    public let id = ProviderID.baseten

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use a personal API key, or a team key that can read "
            + "billing.")
    }

    struct Summary: Decodable {
        let dedicatedUsage: Product?
        let trainingUsage: Product?
        let modelApisUsage: Product?
        let loopsUsage: Product?

        struct Product: Decodable {
            let total: FlexibleDecimal
        }

        enum CodingKeys: String, CodingKey, CaseIterable {
            case dedicatedUsage = "dedicated_usage"
            case trainingUsage = "training_usage"
            case modelApisUsage = "model_apis_usage"
            case loopsUsage = "loops_usage"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Every product may be null, but a reply with none of them isn't a usage summary.
            guard CodingKeys.allCases.contains(where: container.contains) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No usage products"))
            }
            dedicatedUsage = try container.decodeIfPresent(Product.self, forKey: .dedicatedUsage)
            trainingUsage = try container.decodeIfPresent(Product.self, forKey: .trainingUsage)
            modelApisUsage = try container.decodeIfPresent(Product.self, forKey: .modelApisUsage)
            loopsUsage = try container.decodeIfPresent(Product.self, forKey: .loopsUsage)
        }

        var total: Decimal {
            [dedicatedUsage, trainingUsage, modelApisUsage, loopsUsage].compactMap { $0?.total.value }.reduce(0, +)
        }
    }

    static func summaryURL(from start: Date, to end: Date) -> URL {
        var components = URLComponents(string: "https://api.baseten.co/v1/billing/usage_summary")!
        components.queryItems = [URLQueryItem(name: "start_date", value: ISO8601.string(start)),
                                 URLQueryItem(name: "end_date", value: ISO8601.string(end))]
        return components.url!
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let headers = ["Authorization": "Bearer \(key)"]
        let window = window(now)
        // A month is at most 31 days, inside Baseten's limit.
        let month = try await api.get(Summary.self, Self.summaryURL(from: window.monthStart, to: window.dayEnd),
                                      headers: headers)
        let today = try await api.get(Summary.self, Self.summaryURL(from: window.dayStart, to: window.dayEnd),
                                      headers: headers)
        return SpendSnapshot(provider: id, today: Money(today.total), month: Money(month.total), fetchedAt: now)
    }
}
