// Response shapes for AnthropicAnalyticsProvider. Field names and docs links are in that file's header.
import Foundation

extension AnthropicAnalyticsProvider {
    struct Page<Row: Decodable & Sendable>: Decodable, Sendable {
        let data: [Row]
        let hasMore: Bool
        let nextPage: String?
        let dataRefreshedAt: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
            case dataRefreshedAt = "data_refreshed_at"
        }
    }

    struct Group: Decodable, Sendable {
        let actor: Actor?
        let apiKeyID: String?
        let workspaceID: String?
        let model: String?

        enum CodingKeys: String, CodingKey {
            case actor
            case apiKeyID = "api_key_id"
            case workspaceID = "workspace_id"
            case model
        }
    }

    struct Actor: Decodable, Sendable {
        let type: String
        let userID: String?
        let emailAddress: String?
        let name: String?
        let serviceAccountID: String?
        let apiKeyID: String?
        let subject: String?
        let provider: FederatedProvider?

        struct FederatedProvider: Decodable, Sendable {
            let type: String
        }

        enum CodingKeys: String, CodingKey {
            case type
            case userID = "user_id"
            case emailAddress = "email_address"
            case name
            case serviceAccountID = "service_account_id"
            case apiKeyID = "api_key_id"
            case subject
            case provider
        }

        /// Nil for an actor type this build doesn't know, so it lands in Unassigned rather than misattributed.
        var unit: AttributionUnit? {
            switch type {
            case "user_actor":
                userID.map { AttributionUnit(provider: .anthropic, kind: .user, externalID: $0, label: name,
                                             ownerEmail: emailAddress) }
            case "service_account_actor":
                serviceAccountID.map { AttributionUnit(provider: .anthropic, kind: .serviceAccount, externalID: $0) }
            case "api_actor":
                apiKeyID.map { AttributionUnit(provider: .anthropic, kind: .apiKey, externalID: $0) }
            case "federated_actor":
                subject.map { AttributionUnit(provider: .anthropic, kind: .federated, externalID: $0,
                                              label: provider.map { "\($0.type.uppercased()) identity" }) }
            default:
                nil
            }
        }
    }

    struct CostRow: Decodable, Sendable {
        let start: Date
        let end: Date
        let group: Group
        let cost: Cost

        struct Cost: Decodable, Sendable {
            let amount: String
            let currency: String?

            func money() throws -> Money {
                guard let money = Money.fromMinorUnits(amount, Currency(currency ?? "USD")) else {
                    throw SpendError.unexpectedResponse
                }
                return money
            }
        }

        enum CodingKeys: String, CodingKey {
            case start = "starting_at"
            case end = "ending_at"
            case group
            case cost
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            start = try decodeDate(container, .start)
            end = try decodeDate(container, .end)
            group = try container.decode(Group.self, forKey: .group)
            cost = try container.decode(Cost.self, forKey: .cost)
        }
    }

    struct UsageRow: Decodable, Sendable {
        let start: Date
        let end: Date
        let group: Group
        let usage: Usage

        struct Usage: Decodable, Sendable {
            let uncachedInput: Int?
            let cacheCreation: UsageCacheCreation?
            let cacheRead: Int?
            let output: Int?
            let requests: Int?

            enum CodingKeys: String, CodingKey {
                case uncachedInput = "uncached_input_tokens"
                case cacheCreation = "cache_creation"
                case cacheRead = "cache_read_input_tokens"
                case output = "output_tokens"
                case requests
            }
        }

        enum CodingKeys: String, CodingKey {
            case start = "starting_at"
            case end = "ending_at"
            case group
            case usage
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            start = try decodeDate(container, .start)
            end = try decodeDate(container, .end)
            group = try container.decode(Group.self, forKey: .group)
            usage = try container.decode(Usage.self, forKey: .usage)
        }
    }

    struct UsageCacheCreation: Decodable, Sendable {
        let ephemeral1h: Int?
        let ephemeral5m: Int?

        enum CodingKeys: String, CodingKey {
            case ephemeral1h = "ephemeral_1h_input_tokens"
            case ephemeral5m = "ephemeral_5m_input_tokens"
        }
    }

    struct ListPage<Item: Decodable & Sendable>: Decodable, Sendable {
        let data: [Item]
        let hasMore: Bool
        let lastID: String?

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case lastID = "last_id"
        }
    }

    struct UserItem: Decodable, Sendable {
        let id: String
        let email: String
        let name: String?
        let role: String?
    }

    struct WorkspaceItem: Decodable, Sendable {
        let id: String
        let name: String?
        let archivedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case archivedAt = "archived_at"
        }
    }

    struct APIKeyItem: Decodable, Sendable {
        let id: String
        let name: String?
        let partialKeyHint: String?
        let status: String?
        let expiresAt: String?
        let principal: Principal?
        let scope: Scope?

        struct Principal: Decodable, Sendable {
            let type: String
            let userID: String?

            enum CodingKeys: String, CodingKey {
                case type
                case userID = "user_id"
            }
        }

        struct Scope: Decodable, Sendable {
            let type: String
            let workspaceID: String?

            enum CodingKeys: String, CodingKey {
                case type
                case workspaceID = "workspace_id"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case partialKeyHint = "partial_key_hint"
            case status
            case expiresAt = "expires_at"
            case principal
            case scope
        }
    }
}

private func decodeDate<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) throws -> Date {
    let text = try container.decode(String.self, forKey: key)
    guard let date = ISO8601.date(text) else {
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not RFC 3339")
    }
    return date
}
