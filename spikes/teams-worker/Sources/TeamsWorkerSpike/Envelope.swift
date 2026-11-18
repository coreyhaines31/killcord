import Crypto
import Foundation

/// What a wrapped data key is bound to. AWS KMS calls this the encryption context: Decrypt fails unless the
/// caller passes exactly the context that Encrypt was given.
public struct EncryptionContext: Sendable, Hashable {
    public let orgID: UUID
    public let connectionID: UUID

    public init(orgID: UUID, connectionID: UUID) {
        self.orgID = orgID
        self.connectionID = connectionID
    }

    /// Sorted key=value pairs, the same shape KMS uses for its `EncryptionContext` map.
    public var pairs: [String: String] {
        ["connection_id": connectionID.uuidString.lowercased(), "org_id": orgID.uuidString.lowercased()]
    }

    var authenticatedData: Data {
        Data(pairs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";").utf8)
    }
}

public enum EnvelopeError: Error, Equatable, Sendable {
    case unknownKey
    /// The context doesn't match, or the bytes were changed. Deliberately one case: say nothing more.
    case cannotDecrypt
}

/// The web app's half of KMS: `kms:Encrypt` only. It can wrap a data key and never unwrap one.
public protocol DataKeyWrapping: Sendable {
    func wrap(_ dataKey: SymmetricKey, keyID: String, context: EncryptionContext) async throws -> Data
}

/// The worker's half of KMS: `kms:Decrypt`. The wrapped blob names its key, as a KMS ciphertext blob does.
public protocol DataKeyUnwrapping: Sendable {
    func unwrap(_ wrapped: Data, context: EncryptionContext) async throws -> SymmetricKey
}

/// A local stand-in for AWS KMS: one AES-256 KMS key per org key id, held in memory. The AWS client
/// will implement the same two protocols with `Encrypt` and `Decrypt` calls.
public final class LocalKeyService: DataKeyWrapping, DataKeyUnwrapping, @unchecked Sendable {
    private let lock = NSLock()
    private var kmsKeys: [String: SymmetricKey] = [:]

    public init() {}

    /// Like `CreateKey`, one per paying org.
    public func createKey(id: String) {
        lock.withLock { kmsKeys[id] = SymmetricKey(size: .bits256) }
    }

    private func kmsKey(_ id: String) throws -> SymmetricKey {
        guard let key = lock.withLock({ kmsKeys[id] }) else { throw EnvelopeError.unknownKey }
        return key
    }

    public func wrap(_ dataKey: SymmetricKey, keyID: String, context: EncryptionContext) async throws -> Data {
        let kmsKey = try kmsKey(keyID)
        let raw = dataKey.withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(raw, using: kmsKey, authenticating: context.authenticatedData)
        guard let combined = sealed.combined, let idBytes = keyID.data(using: .utf8), idBytes.count < 256 else {
            throw EnvelopeError.unknownKey
        }
        return Data([UInt8(idBytes.count)]) + idBytes + combined
    }

    public func unwrap(_ wrapped: Data, context: EncryptionContext) async throws -> SymmetricKey {
        let bytes = [UInt8](wrapped)
        guard let length = bytes.first.map(Int.init), bytes.count > 1 + length,
              let keyID = String(bytes: bytes[1...length], encoding: .utf8) else {
            throw EnvelopeError.cannotDecrypt
        }
        let kmsKey = try kmsKey(keyID)
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[(1 + length)...]))
            return SymmetricKey(data: try AES.GCM.open(box, using: kmsKey, authenticating: context.authenticatedData))
        } catch {
            throw EnvelopeError.cannotDecrypt
        }
    }
}

/// A stored provider key: the key encrypted with a fresh data key, and that data key wrapped by the org's
/// KMS key. Both are bound to the org and connection.
public struct SealedKey: Sendable, Equatable {
    public var ciphertext: Data
    public var wrappedDataKey: Data

    public init(ciphertext: Data, wrappedDataKey: Data) {
        self.ciphertext = ciphertext
        self.wrappedDataKey = wrappedDataKey
    }
}

public enum Envelope {
    /// Web side: AES-256-GCM with a new data key per stored key, then `kms:Encrypt` on the data key.
    public static func seal(_ plaintext: Data, keyID: String, context: EncryptionContext,
                            wrapper: DataKeyWrapping) async throws -> SealedKey {
        let dataKey = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(plaintext, using: dataKey, authenticating: context.authenticatedData)
        guard let combined = sealed.combined else { throw EnvelopeError.cannotDecrypt }
        let wrapped = try await wrapper.wrap(dataKey, keyID: keyID, context: context)
        return SealedKey(ciphertext: combined, wrappedDataKey: wrapped)
    }

    /// Worker side: `kms:Decrypt` on the data key, then open the key. Fails if the row was moved.
    public static func open(_ sealed: SealedKey, context: EncryptionContext,
                            unwrapper: DataKeyUnwrapping) async throws -> Data {
        let dataKey = try await unwrapper.unwrap(sealed.wrappedDataKey, context: context)
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.ciphertext)
            return try AES.GCM.open(box, using: dataKey, authenticating: context.authenticatedData)
        } catch {
            throw EnvelopeError.cannotDecrypt
        }
    }
}
