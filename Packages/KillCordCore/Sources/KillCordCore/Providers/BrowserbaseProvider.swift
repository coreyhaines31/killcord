// Browserbase project usage: browser minutes and proxy bytes. Browserbase reports units, not money.
// Usage: https://docs.browserbase.com/reference/api/get-project-usage
// Projects: https://docs.browserbase.com/reference/api/list-projects
//
// GET https://api.browserbase.com/v1/projects   (only when no project ID is saved, and only if the key sees one)
//   headers: X-BB-API-Key: <API key>
//   200:     [{ "id": "…", "name": "…", "ownerId": "…", "defaultTimeout": 300, "concurrency": 1, … }]
// GET https://api.browserbase.com/v1/projects/{id}/usage
//   200:     { "browserMinutes": 1234, "proxyBytes": 567890 }
// Both are non-negative integers. The docs don't say what period they cover, so Kill Cord doesn't call it a month.
import Foundation

public struct BrowserbaseProvider: SpendProvider {
    public let id = ProviderID.browserbase
    static let projectsURL = URL(string: "https://api.browserbase.com/v1/projects")!
    static let bytesPerGB = Decimal(1_000_000_000)

    private let api: APIRequester

    public init(http: HTTPClient) {
        api = APIRequester(http: http, missingScopeHint: "Use the API key from your Browserbase project's "
            + "settings.")
    }

    struct Project: Decodable {
        let id: String
    }

    struct Usage: Decodable {
        let browserMinutes: FlexibleDecimal
        let proxyBytes: FlexibleDecimal
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await fetchSpend(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let key = try credentials.require("apiKey")
        let headers = ["X-BB-API-Key": key]
        let project: String
        if let saved = credentials["projectID"] {
            // It goes into the path, so only the characters an ID can have.
            guard FieldFormat.isIdentifier(saved) else {
                throw SpendError.requiresSetup("the project ID doesn't look right. Copy it from the project's "
                    + "settings.")
            }
            project = saved
        } else {
            let projects = try await api.get([Project].self, Self.projectsURL, headers: headers)
            guard projects.count == 1, let only = projects.first, FieldFormat.isIdentifier(only.id) else {
                throw SpendError.requiresSetup(projects.isEmpty
                    ? "this key can't see a project."
                    : "this key can see \(projects.count) projects. Add the project ID to choose one.")
            }
            project = only.id
        }
        let url = Self.projectsURL.appendingPathComponent(project).appendingPathComponent("usage")
        let usage = try await api.get(Usage.self, url, headers: headers)
        let metrics = [
            UsageMetric(id: "browserMinutes", name: "Browser time", value: usage.browserMinutes.value,
                        unit: "minutes"),
            UsageMetric(id: "proxyData", name: "Proxy data", value: usage.proxyBytes.value / Self.bytesPerGB,
                        unit: "GB")
        ]
        return SpendSnapshot(provider: id, today: nil, month: nil, usage: metrics, fetchedAt: now)
    }
}
