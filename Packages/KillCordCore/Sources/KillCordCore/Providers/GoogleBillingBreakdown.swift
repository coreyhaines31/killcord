// Google Cloud spend by project, project label or resource label, from the Cloud Billing export to BigQuery
// (Kill Cord Teams, unit 9). Same table, credentials and query path as GoogleCloudProvider. Read 2026-11-18:
//   Standard schema: https://docs.cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/standard-usage
//   Example queries: https://docs.cloud.google.com/billing/docs/how-to/bq-examples
//   jobs.query:      https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/query
//
// Fields used: project.id ("The ID of the Google Cloud project that generated the Cloud Billing data"),
// project.name, project.labels.key/value ("labels on the project where the usage occurred"), labels.key/value
// ("labels on the resource where the usage occurred"), cost, credits.amount, currency, invoice.month, export_time.
// The schema has no user, principal or API key column, so Google spend is never per person: an admin assigns a
// project or label to someone. Rows with no project (some account-level charges) or without the chosen label key
// are Unassigned.
//
// The standard export "doesn't include any resource-level cost data"; resource labels still appear on its rows.
// Net cost is cost plus credits, cast to NUMERIC and returned as strings (as GoogleCloudProvider does), so money
// never passes through a float. Grouping uses a scalar subquery per row (one label value per key), so a row is
// never counted twice. The label key is a query parameter, never part of the SQL text.
//
// POST https://bigquery.googleapis.com/bigquery/v2/projects/{projectId}/queries   (the only write: a read query)
// then, if jobComplete is false, GET …/queries/{jobId}?location=…&timeoutMs=… until it completes.
//
// UNVERIFIED: the docs list project.labels and labels as structs; the examples UNNEST them, so they're read as
// repeated key/value records.
import Foundation

public struct GoogleBillingBreakdown: Sendable {
    public enum Dimension: Equatable, Sendable {
        case project
        /// One key in `project.labels`, for example "team".
        case projectLabel(String)
        /// One key in the resource `labels`, for example "env".
        case resourceLabel(String)

        var attribution: AttributionDimension {
            switch self {
            case .project: .project
            case .projectLabel: .projectLabel
            case .resourceLabel: .resourceLabel
            }
        }

        var labelKey: String? {
            switch self {
            case .project: nil
            case let .projectLabel(key), let .resourceLabel(key): key
            }
        }
    }

    private let api: APIRequester
    private let tokens: GoogleTokenSource
    private let google: GoogleCloudProvider

    public init(http: HTTPClient, signer: RS256Signer = PlatformRS256Signer.make()) {
        api = APIRequester(http: http, missingScopeHint: "Give the service account BigQuery Data Viewer on the "
            + "export dataset and BigQuery Job User on its project.")
        tokens = GoogleTokenSource(http: http, signer: signer)
        google = GoogleCloudProvider(http: http, signer: signer)
    }

    /// Google label keys: lowercase letters, digits, underscores and dashes, starting with a letter, up to 63.
    static func isLabelKey(_ key: String) -> Bool {
        key.range(of: #"^[a-z][a-z0-9_-]{0,62}$"#, options: .regularExpression) != nil
    }

    static func query(_ table: GoogleCloudProvider.TableName, _ dimension: Dimension) -> String {
        let net = "CAST(cost AS NUMERIC) + IFNULL((SELECT SUM(CAST(c.amount AS NUMERIC)) FROM UNNEST(credits) c), 0)"
        let unit, name: String
        switch dimension {
        case .project:
            (unit, name) = ("project.id", "ANY_VALUE(project.name)")
        case .projectLabel:
            (unit, name) = ("(SELECT l.value FROM UNNEST(project.labels) l WHERE l.key = @label_key LIMIT 1)",
                            "CAST(NULL AS STRING)")
        case .resourceLabel:
            (unit, name) = ("(SELECT l.value FROM UNNEST(labels) l WHERE l.key = @label_key LIMIT 1)",
                            "CAST(NULL AS STRING)")
        }
        return """
        SELECT currency, \(unit) AS unit_id, \(name) AS unit_name, CAST(SUM(\(net)) AS STRING) AS net
        FROM \(table.sql)
        WHERE invoice.month = @invoice_month
        GROUP BY currency, unit_id
        """
    }

    func request(_ setup: GoogleCloudProvider.Setup, token: String, window: BillingWindow,
                 dimension: Dimension) throws -> HTTPRequest {
        var parameters: [[String: Any]] = [
            ["name": "invoice_month", "parameterType": ["type": "STRING"],
             "parameterValue": ["value": window.monthKey.replacingOccurrences(of: "-", with: "")]]
        ]
        if let key = dimension.labelKey {
            parameters.append(["name": "label_key", "parameterType": ["type": "STRING"],
                               "parameterValue": ["value": key]])
        }
        let body: [String: Any] = [
            "query": Self.query(setup.table, dimension), "useLegacySql": false, "parameterMode": "NAMED",
            "timeoutMs": 20000, "queryParameters": parameters
        ]
        let url = GoogleCloudProvider.bigQueryBase.appendingPathComponent(setup.jobProject)
            .appendingPathComponent("queries")
        return HTTPRequest(method: .post, url: url,
                           headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json",
                                     "accept": "application/json"],
                           body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
    }

    /// Runs a query and waits for it a few times, as GoogleCloudProvider does.
    func run(_ request: HTTPRequest, jobProject: String,
             token: String) async throws -> GoogleCloudProvider.QueryResponse {
        var response = try api.decode(GoogleCloudProvider.QueryResponse.self, from: try await api.send(request))
        for _ in 0..<3 where response.jobComplete == false {
            guard let job = response.jobReference, let jobID = job.jobId, FieldFormat.isIdentifier(jobID) else {
                throw SpendError.unexpectedResponse
            }
            var items = [URLQueryItem(name: "timeoutMs", value: "20000")]
            if let location = job.location { items.append(URLQueryItem(name: "location", value: location)) }
            let url = GoogleCloudProvider.bigQueryBase.appendingPathComponent(jobProject)
                .appendingPathComponent("queries").appendingPathComponent(jobID).adding(items)
            response = try await api.get(GoogleCloudProvider.QueryResponse.self, url,
                                         headers: ["Authorization": "Bearer \(token)"])
        }
        switch response.jobComplete {
        case true?: return response
        case false?: throw SpendError.network
        case nil: throw SpendError.unexpectedResponse
        }
    }

    /// The current invoice month's net cost by one dimension, with the export's own total for the same month.
    public func costReport(_ credentials: ProviderCredentials, by dimension: Dimension,
                           now: Date) async throws -> AttributionReport {
        if let key = dimension.labelKey, !Self.isLabelKey(key) {
            throw SpendError.requiresSetup("a Google label key uses lowercase letters, digits, _ and -.")
        }
        let setup = try google.setup(credentials)
        let window = google.window(now)
        let token = try await tokens.token(for: setup.account, scope: GoogleCloudProvider.bigQueryScope, now: now)

        let grouped = try await run(try request(setup, token: token, window: window, dimension: dimension),
                                    jobProject: setup.jobProject, token: token)
        var rows: [AttributedSpend] = []
        var units: [String: AttributionUnit] = [:]
        for row in grouped.rows ?? [] {
            guard row.f.count == 4, let code = row.f[0].v, let money = Money(row.f[3].v ?? "0", Currency(code))
            else { throw SpendError.unexpectedResponse }
            var unit: AttributionUnitRef?
            if let value = row.f[1].v, !value.isEmpty {
                switch dimension {
                case .project:
                    unit = AttributionUnitRef(kind: .project, externalID: value)
                    units[value] = AttributionUnit(provider: .google, kind: .project, externalID: value,
                                                   label: row.f[2].v)
                case let .projectLabel(key), let .resourceLabel(key):
                    let id = "\(key)=\(value)"
                    unit = AttributionUnitRef(kind: .label, externalID: id)
                    units[id] = AttributionUnit(provider: .google, kind: .label, externalID: id,
                                                label: "\(key): \(value)")
                }
            }
            rows.append(AttributedSpend(bucketStart: window.monthStart, bucketEnd: window.dayEnd, unit: unit,
                                        amount: money))
        }

        // The total comes from GoogleCloudProvider's own month query, not from summing the rows above.
        let totals = try await run(try google.queryRequest(setup, token: token, window: window),
                                   jobProject: setup.jobProject, token: token)
        var total = MoneyTotals()
        var lastExport: Date?
        for row in totals.rows ?? [] {
            guard row.f.count == 4, let code = row.f[0].v, let month = Money(row.f[1].v ?? "0", Currency(code))
            else { throw SpendError.unexpectedResponse }
            total.add(month)
            lastExport = row.f[3].v.flatMap(ISO8601.date)
        }
        return AttributionReport(provider: .google, dimension: dimension.attribution, rangeStart: window.monthStart,
                                 rangeEnd: window.dayEnd, rows: rows, providerTotal: total,
                                 dataRefreshedAt: lastExport, meaningVerified: true,
                                 units: units.values.sorted { $0.externalID < $1.externalID })
    }
}
