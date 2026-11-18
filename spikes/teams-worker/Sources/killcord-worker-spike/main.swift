import Foundation
import KillCordCore
import PostgresNIO
import TeamsWorkerSpike

// One drain of due connections against a throwaway database, with a mock provider and a fresh local
// key service. It shows the worker binary links and runs on Linux; the tests prove the behavior.
let env = ProcessInfo.processInfo.environment
let client = PostgresClient(configuration: .init(
    host: env["KC_SPIKE_PGHOST"] ?? "localhost", port: Int(env["KC_SPIKE_PGPORT"] ?? "") ?? 5432,
    username: "kc_spike_worker", password: "spike-only-not-real",
    database: env["KC_SPIKE_PGDATABASE"] ?? "kc_spike", tls: .disable))
let http = MockHTTPClient(routes: ["/organization/costs": HTTPResponse(status: 200, json: #"{"data":[],"has_more":false}"#)])
let worker = Worker(name: "cli", client: client, unwrapper: LocalKeyService()) { _ in OpenAIProvider(http: http) }

try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { await client.run() }
    let outcomes = try await worker.drain(batch: 10, now: Date())
    print("killcord-worker-spike: \(outcomes.count) connections handled")
    group.cancelAll()
}
