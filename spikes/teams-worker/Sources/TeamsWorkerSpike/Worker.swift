import Foundation
import KillCordCore
import PostgresNIO

/// One leased row: enough to decrypt and poll, nothing about people.
public struct LeasedConnection: Sendable, Equatable {
    public let id: UUID
    public let orgID: UUID
    public let provider: ProviderID
    public let sealed: SealedKey

    public var context: EncryptionContext { EncryptionContext(orgID: orgID, connectionID: id) }
}

public enum PollOutcome: Sendable, Equatable {
    case polled(connectionID: UUID, month: Decimal?)
    case failed(connectionID: UUID, reason: String)
}

/// The polling worker. It connects as the worker database role, which can read ciphertext and write
/// readings but has no access to users, sessions or billing.
public struct Worker: Sendable {
    public let name: String
    let client: PostgresClient
    let unwrapper: DataKeyUnwrapping
    let providers: @Sendable (ProviderID) -> SpendProvider?
    let leaseSeconds: Int
    let pollIntervalSeconds: Int

    public init(name: String, client: PostgresClient, unwrapper: DataKeyUnwrapping,
                leaseSeconds: Int = 60, pollIntervalSeconds: Int = 900,
                providers: @escaping @Sendable (ProviderID) -> SpendProvider?) {
        self.name = name
        self.client = client
        self.unwrapper = unwrapper
        self.leaseSeconds = leaseSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
        self.providers = providers
    }

    /// Claims up to `limit` due connections in one statement. `FOR UPDATE SKIP LOCKED` makes concurrent
    /// workers pass over rows another worker is claiming; the lease column keeps them off it afterwards.
    public func lease(limit: Int) async throws -> [LeasedConnection] {
        let rows = try await client.query("""
            UPDATE connections SET lease_owner = \(name),
                lease_until = now() + make_interval(secs => \(leaseSeconds))
            WHERE id IN (
                SELECT id FROM connections
                WHERE next_poll_at <= now() AND (lease_until IS NULL OR lease_until < now())
                ORDER BY next_poll_at
                LIMIT \(limit)
                FOR UPDATE SKIP LOCKED)
            RETURNING id, org_id, provider, key_ciphertext, wrapped_data_key
            """)
        var leased: [LeasedConnection] = []
        for try await (id, orgID, provider, ciphertext, wrapped) in rows.decode((UUID, UUID, String, ByteBuffer,
                                                                                 ByteBuffer).self) {
            guard let providerID = ProviderID(rawValue: provider) else { continue }
            leased.append(LeasedConnection(id: id, orgID: orgID, provider: providerID,
                                           sealed: SealedKey(ciphertext: Data(buffer: ciphertext),
                                                             wrappedDataKey: Data(buffer: wrapped))))
        }
        return leased
    }

    /// Decrypt in memory, poll once, write the reading, release the lease.
    public func poll(_ connection: LeasedConnection, now: Date) async throws -> PollOutcome {
        let snapshot: SpendSnapshot
        do {
            let plaintext = try await Envelope.open(connection.sealed, context: connection.context,
                                                    unwrapper: unwrapper)
            let credentials = try JSONDecoder().decode(ProviderCredentials.self, from: plaintext)
            guard credentials.provider == connection.provider, let adapter = providers(connection.provider) else {
                return try await release(connection, error: "provider mismatch")
            }
            snapshot = try await adapter.fetchSpend(credentials, now: now)
        } catch let error as EnvelopeError {
            return try await release(connection, error: "cannot decrypt (\(error))")
        } catch let error as SpendError {
            return try await release(connection, error: "provider error (\(error))")
        }
        let month = snapshot.month?.amount
        let today = snapshot.today?.amount
        try await client.query("""
            INSERT INTO spend_readings (connection_id, org_id, month, today, fetched_at, worker)
            VALUES (\(connection.id), \(connection.orgID), \(month), \(today), \(snapshot.fetchedAt), \(name))
            """)
        try await client.query("""
            UPDATE connections SET lease_owner = NULL, lease_until = NULL, last_error = NULL,
                next_poll_at = now() + make_interval(secs => \(pollIntervalSeconds))
            WHERE id = \(connection.id) AND lease_owner = \(name)
            """)
        return .polled(connectionID: connection.id, month: month)
    }

    private func release(_ connection: LeasedConnection, error: String) async throws -> PollOutcome {
        try await client.query("""
            UPDATE connections SET lease_owner = NULL, lease_until = NULL, last_error = \(error),
                next_poll_at = now() + make_interval(secs => \(pollIntervalSeconds))
            WHERE id = \(connection.id) AND lease_owner = \(name)
            """)
        return .failed(connectionID: connection.id, reason: error)
    }

    /// Lease and poll until nothing is due. Returns every outcome, in order.
    public func drain(batch: Int, now: Date) async throws -> [PollOutcome] {
        var outcomes: [PollOutcome] = []
        while true {
            let leased = try await lease(limit: batch)
            if leased.isEmpty { return outcomes }
            for connection in leased {
                outcomes.append(try await poll(connection, now: now))
            }
        }
    }
}
