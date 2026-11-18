import Foundation
import KillCordCore
import PostgresNIO
@testable import TeamsWorkerSpike
import Testing

/// Needs a throwaway Postgres prepared by `sql/check-roles.sh` (schema and roles). Skipped without
/// KC_SPIKE_PGHOST, so `swift test` still runs the envelope tests anywhere.
enum SpikeDatabase {
    static let env = ProcessInfo.processInfo.environment
    static var enabled: Bool { env["KC_SPIKE_PGHOST"] != nil }

    static func client(user: String, password: String?) -> PostgresClient {
        PostgresClient(configuration: .init(
            host: env["KC_SPIKE_PGHOST"] ?? "localhost", port: Int(env["KC_SPIKE_PGPORT"] ?? "") ?? 5432,
            username: user, password: password, database: env["KC_SPIKE_PGDATABASE"] ?? "kc_spike", tls: .disable))
    }

    static var owner: PostgresClient {
        client(user: env["KC_SPIKE_OWNER"] ?? "postgres", password: env["KC_SPIKE_OWNER_PASSWORD"])
    }

    static var worker: PostgresClient { client(user: "kc_spike_worker", password: "spike-only-not-real") }

    /// Runs `body` with every client's connection pool running.
    static func with<T: Sendable>(_ clients: [PostgresClient],
                                  _ body: @Sendable @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            for client in clients { group.addTask { await client.run(); return nil } }
            group.addTask { try await body() }
            while let next = try await group.next() {
                if let value = next {
                    group.cancelAll()
                    return value
                }
            }
            throw CancellationError()
        }
    }
}

/// A mock OpenAI that returns one day's costs and records the key it was called with.
func mockOpenAI() -> MockHTTPClient {
    MockHTTPClient(routes: ["/organization/costs": HTTPResponse(status: 200, json: """
        {"object":"page","data":[{"object":"bucket","start_time":1794700800,"end_time":1794787200,"results":[
        {"object":"organization.costs.result","amount":{"value":2.5,"currency":"usd"}}]}],"has_more":false}
        """)])
}

let fakeOpenAIKey = "sk-admin-TEST-openai-secret-0002"
let spikeNow = Date(timeIntervalSince1970: 1_794_767_400)

/// Clears the tables and seeds `count` due OpenAI connections spread over `orgs` orgs, each with its own
/// sealed fake key. Returns the connection ids.
func seed(_ owner: PostgresClient, keys: LocalKeyService, orgs: Int, count: Int) async throws -> [UUID] {
    try await owner.query("TRUNCATE spend_readings, connections, sessions, users, orgs CASCADE")
    let orgIDs = (0..<orgs).map { _ in UUID() }
    for (index, org) in orgIDs.enumerated() {
        keys.createKey(id: org.uuidString)
        try await owner.query("INSERT INTO orgs (id, name) VALUES (\(org), \("Org \(index)"))")
    }
    var ids: [UUID] = []
    for index in 0..<count {
        let org = orgIDs[index % orgs]
        let id = UUID()
        let plaintext = try JSONEncoder().encode(ProviderCredentials(provider: .openai,
                                                                     values: ["apiKey": fakeOpenAIKey]))
        let sealed = try await Envelope.seal(plaintext, keyID: org.uuidString,
                                             context: EncryptionContext(orgID: org, connectionID: id), wrapper: keys)
        try await owner.query("""
            INSERT INTO connections (id, org_id, provider, key_ciphertext, wrapped_data_key, next_poll_at)
            VALUES (\(id), \(org), 'openai', \(ByteBuffer(data: sealed.ciphertext)),
                    \(ByteBuffer(data: sealed.wrappedDataKey)), now() - interval '1 minute')
            """)
        ids.append(id)
    }
    return ids
}

@Suite(.serialized, .enabled(if: SpikeDatabase.enabled)) struct WorkerTests {
    @Test func concurrentWorkersNeverTakeTheSameRow() async throws {
        let keys = LocalKeyService()
        let owner = SpikeDatabase.owner
        let workers = (1...4).map { _ in SpikeDatabase.worker }
        let http = mockOpenAI()
        let results = try await SpikeDatabase.with([owner] + workers) {
            let ids = try await seed(owner, keys: keys, orgs: 5, count: 400)
            let outcomes = try await withThrowingTaskGroup(of: (String, [PollOutcome]).self) { group in
                for (index, client) in workers.enumerated() {
                    group.addTask {
                        let worker = Worker(name: "w\(index + 1)", client: client, unwrapper: keys) { _ in
                            OpenAIProvider(http: http)
                        }
                        return (worker.name, try await worker.drain(batch: 3, now: spikeNow))
                    }
                }
                var all: [(String, [PollOutcome])] = []
                for try await result in group { all.append(result) }
                return all
            }
            var readings: [(UUID, String)] = []
            for try await row in try await owner.query("SELECT connection_id, worker FROM spend_readings")
                .decode((UUID, String).self) { readings.append(row) }
            return (ids, outcomes, readings)
        }
        let (ids, outcomes, readings) = results
        let polled = outcomes.flatMap(\.1)
        let polledIDs = polled.compactMap { outcome -> UUID? in
            if case .polled(let id, let month) = outcome, month == Decimal(string: "2.5") { return id }
            return nil
        }
        #expect(polledIDs.count == ids.count)
        #expect(Set(polledIDs) == Set(ids))
        #expect(readings.count == ids.count)
        #expect(Set(readings.map(\.0)).count == ids.count)
        #expect(http.requests.allSatisfy { $0.headers["Authorization"] == "Bearer \(fakeOpenAIKey)" })
        #expect(http.requests.allSatisfy { $0.url.host == "api.openai.com" && $0.method == .get })
        let perWorker = Dictionary(grouping: readings, by: \.1).mapValues(\.count)
        print("spike: rows per worker \(perWorker.sorted { $0.key < $1.key })")
    }

    @Test func aCiphertextCopiedToAnotherOrgFailsToDecrypt() async throws {
        let keys = LocalKeyService()
        let owner = SpikeDatabase.owner
        let client = SpikeDatabase.worker
        let http = mockOpenAI()
        let outcomes = try await SpikeDatabase.with([owner, client]) {
            let ids = try await seed(owner, keys: keys, orgs: 2, count: 2)
            // An attacker with write access to the table copies org 0's sealed key onto org 1's row, and
            // onto a new row in the same org: both must fail, since the context names org and connection.
            try await owner.query("""
                UPDATE connections AS target
                SET key_ciphertext = source.key_ciphertext, wrapped_data_key = source.wrapped_data_key
                FROM connections AS source WHERE source.id = \(ids[0]) AND target.id = \(ids[1])
                """)
            let sameOrgCopy = UUID()
            try await owner.query("""
                INSERT INTO connections (id, org_id, provider, key_ciphertext, wrapped_data_key, next_poll_at)
                SELECT \(sameOrgCopy), org_id, provider, key_ciphertext, wrapped_data_key, next_poll_at
                FROM connections WHERE id = \(ids[0])
                """)
            let worker = Worker(name: "w1", client: client, unwrapper: keys) { _ in OpenAIProvider(http: http) }
            return (ids + [sameOrgCopy], try await worker.drain(batch: 10, now: spikeNow))
        }
        let (ids, results) = outcomes
        #expect(results.contains(.polled(connectionID: ids[0], month: Decimal(string: "2.5"))))
        func failedToDecrypt(_ id: UUID) -> Bool {
            results.contains { outcome in
                if case .failed(id, let reason) = outcome { return reason.hasPrefix("cannot decrypt") }
                return false
            }
        }
        #expect(failedToDecrypt(ids[1]))
        #expect(failedToDecrypt(ids[2]))
        #expect(http.requests.count == 1)
    }
}
