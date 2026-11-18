import Crypto
import Foundation
import KillCordCore
@testable import TeamsWorkerSpike
import Testing

@Suite struct EnvelopeTests {
    let orgA = UUID()
    let orgB = UUID()
    let connection = UUID()
    let plaintext = Data("sk-admin-TEST-openai-secret-0002".utf8)

    func service() -> LocalKeyService {
        let keys = LocalKeyService()
        keys.createKey(id: "org-a")
        keys.createKey(id: "org-b")
        return keys
    }

    @Test func roundTrips() async throws {
        let keys = service()
        let context = EncryptionContext(orgID: orgA, connectionID: connection)
        let sealed = try await Envelope.seal(plaintext, keyID: "org-a", context: context, wrapper: keys)
        #expect(!sealed.ciphertext.contains(plaintext))
        #expect(try await Envelope.open(sealed, context: context, unwrapper: keys) == plaintext)
    }

    @Test func failsUnderAnotherOrg() async throws {
        let keys = service()
        let sealed = try await Envelope.seal(plaintext, keyID: "org-a",
                                             context: EncryptionContext(orgID: orgA, connectionID: connection),
                                             wrapper: keys)
        await #expect(throws: EnvelopeError.cannotDecrypt) {
            try await Envelope.open(sealed, context: EncryptionContext(orgID: orgB, connectionID: connection),
                                    unwrapper: keys)
        }
    }

    @Test func failsUnderAnotherConnection() async throws {
        let keys = service()
        let sealed = try await Envelope.seal(plaintext, keyID: "org-a",
                                             context: EncryptionContext(orgID: orgA, connectionID: connection),
                                             wrapper: keys)
        await #expect(throws: EnvelopeError.cannotDecrypt) {
            try await Envelope.open(sealed, context: EncryptionContext(orgID: orgA, connectionID: UUID()),
                                    unwrapper: keys)
        }
    }

    @Test func failsWhenTheDataKeyIsSwapped() async throws {
        let keys = service()
        let context = EncryptionContext(orgID: orgA, connectionID: connection)
        let first = try await Envelope.seal(plaintext, keyID: "org-a", context: context, wrapper: keys)
        let second = try await Envelope.seal(Data("other".utf8), keyID: "org-a", context: context, wrapper: keys)
        let mixed = SealedKey(ciphertext: first.ciphertext, wrappedDataKey: second.wrappedDataKey)
        await #expect(throws: EnvelopeError.cannotDecrypt) {
            try await Envelope.open(mixed, context: context, unwrapper: keys)
        }
    }

    @Test func failsWithoutTheOrgKMSKey() async throws {
        let keys = service()
        let context = EncryptionContext(orgID: orgA, connectionID: connection)
        let sealed = try await Envelope.seal(plaintext, keyID: "org-a", context: context, wrapper: keys)
        await #expect(throws: EnvelopeError.unknownKey) {
            try await Envelope.open(sealed, context: context, unwrapper: LocalKeyService())
        }
    }

    @Test func contextMatchesTheKMSMapShape() {
        let context = EncryptionContext(orgID: orgA, connectionID: connection)
        #expect(context.pairs == ["org_id": orgA.uuidString.lowercased(),
                                  "connection_id": connection.uuidString.lowercased()])
    }
}
