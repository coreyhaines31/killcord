// Google Cloud and Gemini spend, from the Cloud Billing export to BigQuery, and budget state from the
// Cloud Billing Budget API.
//
// Why BigQuery: the Cloud Billing API (cloudbilling.googleapis.com) has no cost data, and the Gemini API
// and AI Studio have no spend API at all. The billing export is the only programmatic source of actual cost.
//   Cloud Billing API: https://docs.cloud.google.com/billing/docs/reference/rest
//   Export overview:   https://docs.cloud.google.com/billing/docs/how-to/export-data-bigquery
//   Standard schema:   https://docs.cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/standard-usage
//   Example queries:   https://docs.cloud.google.com/billing/docs/how-to/bq-examples
//   jobs.query:        https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/query
//   getQueryResults:   https://docs.cloud.google.com/bigquery/docs/reference/v2/jobs/getQueryResults
//
// POST https://bigquery.googleapis.com/bigquery/v2/projects/{projectId}/queries
//   headers: Authorization: Bearer <token for scope bigquery.readonly>
//   body:    { query, useLegacySql: false, parameterMode: "NAMED", queryParameters, timeoutMs }
//   200:     { jobComplete, jobReference: { projectId, jobId, location }, schema, rows: [{ f: [{ v: "…" }] }] }
// If jobComplete is false, poll GET …/projects/{projectId}/queries/{jobId}?location=…&timeoutMs=….
// The query casts cost to NUMERIC and returns strings, so money never passes through a float.
// Export latency: "Typically, your cost details are available within a day, but can sometimes take more
// than 24 hours", with no guarantee. Google's billing day and invoice month follow US Pacific time.
//
// Budgets: https://docs.cloud.google.com/billing/docs/reference/budget/rest/v1/billingAccounts.budgets/list
// Spend caps: https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps
// GET https://billingbudgets.googleapis.com/v1/billingAccounts/{billingAccountId}/budgets?pageSize=100
//   headers: Authorization: Bearer <token for scope cloud-billing>
//   200:     { budgets: [{ displayName, amount: { specifiedAmount: { currencyCode, units: "50", nanos } },
//              thresholdRules, spendCap: { inputState, outputState: CONFIGURED | ENFORCED | … } }],
//              nextPageToken }
// The Budget API returns no current spend, but it's the only API that says whether a spend cap exists and
// whether it's paused usage. Alerts-only budgets never stop spending.
import Foundation

public struct GoogleCloudProvider: SpendProvider {
    public let id = ProviderID.google
    public static let spendCapID = "google.spend-cap-budget"
    public static let budgetAlertCapID = "google.budget-alert"
    static let bigQueryScope = "https://www.googleapis.com/auth/bigquery.readonly"
    static let billingScope = "https://www.googleapis.com/auth/cloud-billing"
    static let bigQueryBase = URL(string: "https://bigquery.googleapis.com/bigquery/v2/projects/")!
    static let budgetsBase = URL(string: "https://billingbudgets.googleapis.com/v1/billingAccounts/")!

    private let api: APIRequester
    private let tokens: GoogleTokenSource

    public init(http: HTTPClient, signer: RS256Signer = PlatformRS256Signer.make()) {
        api = APIRequester(http: http, missingScopeHint: "Give the service account BigQuery Data Viewer on the "
            + "export dataset and BigQuery Job User on its project.")
        tokens = GoogleTokenSource(http: http, signer: signer)
    }

    /// A fully qualified table, `project.dataset.table`. Checked strictly because table names can't be query
    /// parameters, so this is what keeps a pasted value from changing the SQL.
    struct TableName: Equatable {
        let project: String
        let dataset: String
        let table: String

        init(_ text: String) throws {
            let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "` \n\t"))
            let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            func valid(_ part: String, allowDash: Bool) -> Bool {
                !part.isEmpty && part.count <= 1024 && part.unicodeScalars.allSatisfy {
                    $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || (allowDash && $0 == "-"))
                }
            }
            guard parts.count == 3, valid(parts[0], allowDash: true), valid(parts[1], allowDash: false),
                  valid(parts[2], allowDash: false)
            else { throw SpendError.requiresSetup("the billing export table must look like project.dataset.table.") }
            (project, dataset, table) = (parts[0], parts[1], parts[2])
        }

        var sql: String { "`\(project).\(dataset).\(table)`" }
    }

    static func query(_ table: TableName) -> String {
        let net = "CAST(cost AS NUMERIC) + IFNULL((SELECT SUM(CAST(c.amount AS NUMERIC)) FROM UNNEST(credits) c), 0)"
        return """
        SELECT currency,
          CAST(SUM(\(net)) AS STRING) AS month_net,
          CAST(SUM(IF(DATE(usage_start_time, 'America/Los_Angeles') = @today, \(net), 0)) AS STRING) AS today_net,
          FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%SZ', MAX(export_time)) AS last_export
        FROM \(table.sql)
        WHERE invoice.month = @invoice_month
        GROUP BY currency
        """
    }

    struct QueryResponse: Decodable {
        struct Row: Decodable {
            struct Cell: Decodable {
                let v: String?
            }

            let f: [Cell]
        }

        struct JobReference: Decodable {
            let projectId: String?
            let jobId: String?
            let location: String?
        }

        let jobComplete: Bool?
        let jobReference: JobReference?
        let rows: [Row]?
    }

    struct BudgetList: Decodable {
        struct Budget: Decodable {
            struct Amount: Decodable {
                struct Specified: Decodable {
                    let currencyCode: String?
                    let units: String?
                    let nanos: Int?
                }

                let specifiedAmount: Specified?
            }

            struct SpendCap: Decodable {
                let outputState: String?
            }

            let displayName: String?
            let amount: Amount?
            let spendCap: SpendCap?
        }

        let budgets: [Budget]?
        let nextPageToken: String?
    }

    struct Setup {
        let account: GoogleServiceAccount
        let table: TableName
        var jobProject: String { account.projectID ?? table.project }
    }

    func setup(_ credentials: ProviderCredentials) throws -> Setup {
        let account = try GoogleServiceAccount.parse(try credentials.require("serviceAccountJSON"))
        let table = try TableName(try credentials.require("exportTable"))
        guard FieldFormat.isIdentifier(account.projectID ?? table.project) else { throw SpendError.invalidKey }
        return Setup(account: account, table: table)
    }

    func queryRequest(_ setup: Setup, token: String, window: BillingWindow) throws -> HTTPRequest {
        let invoiceMonth = window.monthKey.replacingOccurrences(of: "-", with: "")
        let body: [String: Any] = [
            "query": Self.query(setup.table),
            "useLegacySql": false,
            "parameterMode": "NAMED",
            "timeoutMs": 20000,
            "queryParameters": [
                ["name": "today", "parameterType": ["type": "DATE"], "parameterValue": ["value": window.dayKey]],
                ["name": "invoice_month", "parameterType": ["type": "STRING"],
                 "parameterValue": ["value": invoiceMonth]]
            ]
        ]
        let url = Self.bigQueryBase.appendingPathComponent(setup.jobProject).appendingPathComponent("queries")
        return HTTPRequest(method: .post, url: url,
                           headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json",
                                     "accept": "application/json"],
                           body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
    }

    func runQuery(_ setup: Setup, now: Date) async throws -> QueryResponse {
        let token = try await tokens.token(for: setup.account, scope: Self.bigQueryScope, now: now)
        var response = try api.decode(QueryResponse.self, from: try await api.send(
            queryRequest(setup, token: token, window: window(now))
        ))
        // A slow query: wait for it a few more times, then give up until the next refresh.
        for _ in 0..<3 where response.jobComplete == false {
            guard let job = response.jobReference, let jobID = job.jobId, FieldFormat.isIdentifier(jobID) else {
                throw SpendError.unexpectedResponse
            }
            var items = [URLQueryItem(name: "timeoutMs", value: "20000")]
            if let location = job.location { items.append(URLQueryItem(name: "location", value: location)) }
            let url = Self.bigQueryBase.appendingPathComponent(setup.jobProject)
                .appendingPathComponent("queries").appendingPathComponent(jobID).adding(items)
            response = try await api.get(QueryResponse.self, url, headers: ["Authorization": "Bearer \(token)"])
        }
        guard response.jobComplete != false else { throw SpendError.network }
        return response
    }

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try await runQuery(try setup(credentials), now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        let response = try await runQuery(try setup(credentials), now: now)
        let rows = response.rows ?? []
        guard rows.count <= 1 else { throw SpendError.unexpectedResponse }
        guard let row = rows.first else {
            // Nothing exported for this invoice month yet.
            return SpendSnapshot(provider: id, today: .zero(), month: .zero(), fetchedAt: now)
        }
        guard row.f.count == 4, let code = row.f[0].v,
              let month = Money(row.f[1].v ?? "0", Currency(code)),
              let today = Money(row.f[2].v ?? "0", Currency(code))
        else { throw SpendError.unexpectedResponse }
        return SpendSnapshot(provider: id, today: today, month: month,
                             dataAsOf: row.f[3].v.flatMap(ISO8601.date), fetchedAt: now)
    }

    static func isBillingAccountID(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9]{6}-[A-Za-z0-9]{6}-[A-Za-z0-9]{6}$"#, options: .regularExpression) != nil
    }

    public func verifyCaps(_ credentials: ProviderCredentials, now: Date) async -> [CapVerification] {
        guard let accountID = credentials["billingAccountID"], Self.isBillingAccountID(accountID),
              let json = credentials["serviceAccountJSON"],
              let account = try? GoogleServiceAccount.parse(json),
              let token = try? await tokens.token(for: account, scope: Self.billingScope, now: now)
        else { return [] }
        var budgets: [BudgetList.Budget] = []
        var pageToken: String?
        for _ in 0..<10 {
            var items = [URLQueryItem(name: "pageSize", value: "100")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let url = Self.budgetsBase.appendingPathComponent(accountID).appendingPathComponent("budgets").adding(items)
            guard let page = try? await api.get(BudgetList.self, url, headers: ["Authorization": "Bearer \(token)"])
            else { return [] }
            budgets += page.budgets ?? []
            guard let next = page.nextPageToken, !next.isEmpty else { break }
            pageToken = next
        }
        return Self.verifications(budgets, now: now)
    }

    static func verifications(_ budgets: [BudgetList.Budget], now: Date) -> [CapVerification] {
        func label(_ budget: BudgetList.Budget) -> String {
            var text = budget.displayName ?? "Unnamed budget"
            if let amount = budget.amount?.specifiedAmount, let units = amount.units, let whole = Decimal(string: units) {
                let money = Money(whole + Decimal(amount.nanos ?? 0) / 1_000_000_000,
                                  Currency(amount.currencyCode ?? "USD"))
                text += " (\(MoneyText.string(money)))"
            }
            return text
        }
        let caps = budgets.filter { $0.spendCap != nil }
        let capStatus: CapVerification.Status
        if let enforced = caps.first(where: { $0.spendCap?.outputState == "ENFORCED" }) {
            capStatus = .enforced("Google reports the spend cap \(label(enforced)) is enforced: usage of its "
                + "service is paused for the rest of the month.")
        } else if !caps.isEmpty {
            capStatus = .on("Google reports a spend cap budget: \(caps.map(label).joined(separator: ", ")).")
        } else {
            capStatus = .off("Google reports no spend cap budget on this billing account.")
        }
        let alertStatus: CapVerification.Status = budgets.isEmpty
            ? .off("Google reports no budgets on this billing account.")
            : .on("Google reports \(budgets.count) budget\(budgets.count == 1 ? "" : "s") with alerts: "
                + budgets.prefix(3).map(label).joined(separator: ", ") + (budgets.count > 3 ? ", …" : "") + ".")
        return [
            CapVerification(capID: spendCapID, status: capStatus, checkedAt: now),
            CapVerification(capID: budgetAlertCapID, status: alertStatus, checkedAt: now)
        ]
    }
}
