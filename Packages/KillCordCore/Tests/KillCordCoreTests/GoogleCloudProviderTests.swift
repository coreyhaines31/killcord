// swiftlint:disable line_length
// Inline JSON fixtures preserve the exact provider response shape.
import Foundation
@testable import KillCordCore
import Testing

@Suite struct GoogleCloudProviderTests {
    func client(query: String = "google-query.json") throws -> MockHTTPClient {
        let token = try json("google-token.json")
        let result = try json(query)
        let budgets = try json("google-budgets.json")
        return MockHTTPClient { request in
            switch request.url.host {
            case "oauth2.googleapis.com": token
            case "billingbudgets.googleapis.com": budgets
            default: result
            }
        }
    }

    @Test func exchangesAJWTAtGoogleOnly() async throws {
        let http = try client()
        let signer = FakeSigner()
        _ = try await GoogleCloudProvider(http: http, signer: signer).fetchSpend(FakeKeys.credentials(.google), now: testNow)
        let tokenRequest = try #require(http.requests.first)
        // The key file's token_uri points elsewhere; it's ignored.
        #expect(tokenRequest.url.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(tokenRequest.method == .post)
        #expect(tokenRequest.headers["Content-Type"] == "application/x-www-form-urlencoded")
        let formData = try #require(tokenRequest.body)
        let form = String(data: formData, encoding: .utf8)!
        #expect(form.hasPrefix("grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion="))

        let jwt = String(form.split(separator: "=").last!)
        let parts = jwt.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        let headerData = try #require(base64URLDecode(parts[0]))
        let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any]
        #expect(header?["alg"] as? String == "RS256")
        #expect(header?["kid"] as? String == "kid123")
        let claimsData = try #require(base64URLDecode(parts[1]))
        let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any]
        #expect(claims?["iss"] as? String == "kill-cord@kc-billing.iam.gserviceaccount.com")
        #expect(claims?["aud"] as? String == "https://oauth2.googleapis.com/token")
        #expect(claims?["scope"] as? String == "https://www.googleapis.com/auth/bigquery.readonly")
        #expect(claims?["iat"] as? Int == 1_794_767_400)
        #expect(claims?["exp"] as? Int == 1_794_767_400 + 3600)
        #expect(signer.signed.first.map { String(data: $0, encoding: .utf8) } == parts[0] + "." + parts[1])
    }

    @Test func queriesTheExportWithParameters() async throws {
        let http = try client()
        let snapshot = try await GoogleCloudProvider(http: http, signer: FakeSigner())
            .fetchSpend(FakeKeys.credentials(.google), now: testNow)
        let query = try #require(http.requests.first { $0.url.host == "bigquery.googleapis.com" })
        #expect(query.method == .post)
        #expect(query.path == "/bigquery/v2/projects/kc-billing/queries")
        #expect(query.headers["Authorization"] == "Bearer ya29.TEST-ACCESS-TOKEN")
        let bodyData = try #require(query.body)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["useLegacySql"] as? Bool == false)
        #expect(body["parameterMode"] as? String == "NAMED")
        let sql = try #require(body["query"] as? String)
        #expect(sql.contains("FROM `kc-billing.billing_export.gcp_billing_export_v1_0123AB_4567CD_89EF01`"))
        #expect(sql.contains("CAST(cost AS NUMERIC)"))
        #expect(sql.contains("UNNEST(credits)"))
        let parameters = try #require(body["queryParameters"] as? [[String: Any]])
        let values = try Dictionary(uniqueKeysWithValues: parameters.map { parameter in
            let name = try #require(parameter["name"] as? String)
            let value = try #require(parameter["parameterValue"] as? [String: Any])
            return (name, try #require(value["value"] as? String))
        })
        // 10:30a Pacific on Nov 15.
        #expect(values == ["today": "2026-11-15", "invoice_month": "202611"])

        #expect(snapshot.month == usd("42.137215"))
        #expect(snapshot.today == usd("3.000001"))
        #expect(snapshot.dataAsOf == ISO8601.date("2026-11-15T11:00:00Z"))
    }

    @Test func reusesTheTokenUntilItExpires() async throws {
        let http = try client()
        let provider = GoogleCloudProvider(http: http, signer: FakeSigner())
        _ = try await provider.fetchSpend(FakeKeys.credentials(.google), now: testNow)
        _ = try await provider.fetchSpend(FakeKeys.credentials(.google), now: testNow.addingTimeInterval(1800))
        #expect(http.requests.filter { $0.url.host == "oauth2.googleapis.com" }.count == 1)
        _ = try await provider.fetchSpend(FakeKeys.credentials(.google), now: testNow.addingTimeInterval(3560))
        #expect(http.requests.filter { $0.url.host == "oauth2.googleapis.com" }.count == 2)
    }

    @Test func waitsForASlowQuery() async throws {
        let token = try json("google-token.json")
        let pending = try json("google-query-pending.json")
        let done = try json("google-query.json")
        let http = MockHTTPClient { request in
            if request.url.host == "oauth2.googleapis.com" { return token }
            return request.method == .post ? pending : done
        }
        let snapshot = try await GoogleCloudProvider(http: http, signer: FakeSigner())
            .fetchSpend(FakeKeys.credentials(.google), now: testNow)
        let poll = try #require(http.requests.last)
        #expect(poll.method == .get)
        #expect(poll.path == "/bigquery/v2/projects/kc-billing/queries/job_abc123")
        #expect(poll.query("location") == ["US"])
        #expect(snapshot.month == usd("42.137215"))
    }

    @Test func noRowsYetIsZero() async throws {
        let token = try json("google-token.json")
        let http = MockHTTPClient { request in
            request.url.host == "oauth2.googleapis.com" ? token
                : HTTPResponse(status: 200, json: #"{"jobComplete":true,"totalRows":"0"}"#)
        }
        let snapshot = try await GoogleCloudProvider(http: http, signer: FakeSigner())
            .fetchSpend(FakeKeys.credentials(.google), now: testNow)
        #expect(snapshot.month == .zero())
    }

    @Test(arguments: [
        "kc-billing.billing.table; DROP TABLE x",
        "kc-billing.billing.table` OR 1=1 --",
        "billing.table",
        "a.b.c.d",
        "kc billing.billing.table",
        "kc-billing.bill-ing.table"
    ])
    func rejectsTableNamesThatCouldChangeTheQuery(_ name: String) async throws {
        let http = try client()
        var values = ["serviceAccountJSON": FakeKeys.googleJSON]
        values["exportTable"] = name
        await #expect(throws: SpendError.self) {
            try await GoogleCloudProvider(http: http, signer: FakeSigner())
                .fetchSpend(ProviderCredentials(provider: .google, values: values), now: testNow)
        }
        #expect(http.requests.isEmpty)
    }

    @Test func acceptsABacktickedTableName() throws {
        let table = try GoogleCloudProvider.TableName("`my-proj.billing.gcp_billing_export_v1_X`")
        #expect(table.sql == "`my-proj.billing.gcp_billing_export_v1_X`")
    }

    @Test func rejectsSomethingThatIsntAServiceAccountKey() async throws {
        let http = try client()
        let credentials = ProviderCredentials(provider: .google, values: [
            "serviceAccountJSON": #"{"type":"authorized_user","client_id":"x"}"#,
            "exportTable": "p.d.t"
        ])
        await #expect(throws: SpendError.invalidKey) {
            try await GoogleCloudProvider(http: http, signer: FakeSigner()).fetchSpend(credentials, now: testNow)
        }
    }

    @Test func aRejectedKeyIsInvalid() async throws {
        let http = MockHTTPClient { _ in HTTPResponse(status: 400, json: #"{"error":"invalid_grant"}"#) }
        await #expect(throws: SpendError.invalidKey) {
            try await GoogleCloudProvider(http: http, signer: FakeSigner())
                .fetchSpend(FakeKeys.credentials(.google), now: testNow)
        }
    }

    @Test func checksBudgetsAndSpendCaps() async throws {
        let http = try client()
        let results = await GoogleCloudProvider(http: http, signer: FakeSigner())
            .verifyCaps(FakeKeys.credentials(.google), now: testNow)
        let budgetRequest = try #require(http.requests.first { $0.url.host == "billingbudgets.googleapis.com" })
        #expect(budgetRequest.path == "/v1/billingAccounts/0123AB-4567CD-89EF01/budgets")
        #expect(budgetRequest.query("pageSize") == ["100"])
        #expect(results.map(\.capID) == [GoogleCloudProvider.spendCapID, GoogleCloudProvider.budgetAlertCapID])
        #expect(results[0].status == .on("Google reports a spend cap budget: Gemini API cap ($50.50)."))
        #expect(results[1].status == .on("Google reports 2 budgets with alerts: Gemini API cap ($50.50), "
            + "Whole account ($300.00)."))
    }

    @Test func reportsAnEnforcedSpendCap() {
        let budget = GoogleCloudProvider.BudgetList.Budget(
            displayName: "Gemini", amount: nil, spendCap: .init(outputState: "ENFORCED"))
        let results = GoogleCloudProvider.verifications([budget], now: testNow)
        guard case .enforced = results[0].status else { Issue.record("Got \(results)"); return }
        let none = GoogleCloudProvider.verifications([], now: testNow)
        #expect(none[0].status == .off("Google reports no spend cap budget on this billing account."))
    }

    @Test func skipsBudgetsWithoutABillingAccount() async throws {
        let http = try client()
        var credentials = FakeKeys.credentials(.google)
        credentials = ProviderCredentials(provider: .google, values: [
            "serviceAccountJSON": credentials["serviceAccountJSON"]!, "exportTable": credentials["exportTable"]!
        ])
        #expect(await GoogleCloudProvider(http: http, signer: FakeSigner()).verifyCaps(credentials, now: testNow).isEmpty)
        #expect(http.requests.isEmpty)
    }

    @Test func unwrapsPKCS8ToPKCS1() throws {
        // A PrivateKeyInfo wrapping the bytes 01 02 03 as the "RSA key".
        let pkcs1: [UInt8] = [0x01, 0x02, 0x03]
        let algorithm: [UInt8] = [0x30, 0x0D, 0x06, 0x09] + PEM.rsaEncryptionOID + [0x05, 0x00]
        let inner: [UInt8] = [0x02, 0x01, 0x00] + algorithm + [0x04, UInt8(pkcs1.count)] + pkcs1
        let der: [UInt8] = [0x30, UInt8(inner.count)] + inner
        let pem = "-----BEGIN PRIVATE KEY-----\n\(Data(der).base64EncodedString())\n-----END PRIVATE KEY-----\n"
        #expect(try PEM.rsaPrivateKey(pem) == Data(pkcs1))

        // Long-form lengths.
        let long = [UInt8](repeating: 0xAB, count: 200)
        var reader = DERReader([0x04, 0x81, 0xC8] + long)
        #expect(try reader.read(tag: 0x04) == long)

        #expect(throws: SpendError.invalidKey) { try PEM.rsaPrivateKey("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----") }
        var truncated = DERReader([0x30, 0x10, 0x01])
        #expect(throws: SpendError.invalidKey) { try truncated.read(tag: 0x30) }
    }
}

// swiftlint:enable line_length
