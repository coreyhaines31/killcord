// Neon usage by project (Kill Cord Teams, unit 9). Usage units, never dollars: the result is a UsageBreakdown,
// which has no Money in it.
// Consumption: https://neon.com/docs/guides/consumption-metrics (read 2026-11-18)
//
// GET https://console.neon.tech/api/v2/consumption_history/v2/projects   (the call NeonProvider makes)
//   query: from, to (RFC 3339), granularity=daily, org_id, metrics (comma-separated), limit (1 to 100), cursor
//   200:   { projects: [{ project_id, periods: [{ period_id, period_plan, period_start, consumption: [{
//            timeframe_start, timeframe_end, metrics: [{ metric_name, value }] }] }] }], pagination: { cursor } }
// "Metrics with a value of zero for a given timeframe may be omitted from the response." Every quantity Neon
// reports belongs to a project, so nothing is unassigned. Raw units are from the same page's metric table.
// Neon has no per-user or per-key data: a "person" here is whoever an admin assigns the project to.
//
// UNVERIFIED: project names. The consumption response carries only project_id, so units are labelled by id.
import Foundation

public struct NeonProjectBreakdown: Sendable {
    /// Raw units for the metrics NeonProvider requests, from the consumption-metrics page.
    static let rawUnits: [String: String] = [
        "compute_unit_seconds": "CU-seconds",
        "root_branch_bytes_month": "byte-months",
        "child_branch_bytes_month": "byte-months",
        "instant_restore_bytes_month": "byte-months",
        "public_network_transfer_bytes": "bytes"
    ]
    static let maxPages = 20

    private let neon: NeonProvider

    public init(http: HTTPClient) {
        neon = NeonProvider(http: http)
    }

    struct Consumption: Decodable {
        struct Project: Decodable {
            let projectID: String
            let periods: [Period]

            enum CodingKeys: String, CodingKey {
                case projectID = "project_id"
                case periods
            }
        }

        struct Period: Decodable {
            let consumption: [Bucket]
        }

        struct Bucket: Decodable {
            let timeframeStart: String
            let timeframeEnd: String?
            let metrics: [NeonProvider.Consumption.Metric]

            enum CodingKeys: String, CodingKey {
                case timeframeStart = "timeframe_start"
                case timeframeEnd = "timeframe_end"
                case metrics
            }
        }

        let projects: [Project]
        let pagination: NeonProvider.Consumption.Pagination?
    }

    /// Daily usage by project for [start, end), with the same metrics and paging as NeonProvider.
    public func projectUsage(_ credentials: ProviderCredentials, from start: Date, to end: Date) async throws
        -> UsageBreakdown {
        let key = try credentials.require("apiKey")
        let orgID = try credentials.require("orgID")
        guard end > start else { throw AttributionRangeError.empty }
        var rows: [AttributedQuantity] = []
        var projectIDs: [String] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            let page = try await neon.send(Consumption.self, try neon.consumptionURL(orgID: orgID, from: start,
                                                                                    to: end, cursor: cursor), key: key)
            for project in page.projects {
                if !projectIDs.contains(project.projectID) { projectIDs.append(project.projectID) }
                let unit = AttributionUnitRef(kind: .project, externalID: project.projectID)
                for bucket in project.periods.flatMap(\.consumption) {
                    guard let bucketStart = ISO8601.date(bucket.timeframeStart) else {
                        throw SpendError.unexpectedResponse
                    }
                    let bucketEnd = bucket.timeframeEnd.flatMap(ISO8601.date) ?? bucketStart.addingTimeInterval(86_400)
                    for metric in bucket.metrics {
                        rows.append(AttributedQuantity(bucketStart: bucketStart, bucketEnd: bucketEnd, unit: unit,
                                                       metric: metric.metricName, quantity: metric.value.value))
                    }
                }
            }
            // A short page is the last one; Neon returns a cursor even then (as NeonProvider reads it).
            guard page.projects.count >= NeonProvider.pageSize, let next = page.pagination?.cursor else { break }
            cursor = next
        }
        return UsageBreakdown(provider: .neon, dimension: .project, rangeStart: start, rangeEnd: end, rows: rows,
                              rawUnits: Self.rawUnits,
                              units: projectIDs.map { AttributionUnit(provider: .neon, kind: .project, externalID: $0) })
    }
}
