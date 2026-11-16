#if canImport(Security)
import Foundation
@testable import KillCordCore
import Security
import Testing

@Suite struct MacSecurityTests {
    @Test func keychainRoundTripAndIsolation() throws {
        let service = "app.killcord.tests.\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        let other = KeychainSecretStore(service: service + ".other")
        defer { try? store.delete(account: "test") }
        #expect(try store.read(account: "test") == nil)
        try store.write(Data("TEST-KEY-one".utf8), account: "test")
        #expect(try store.read(account: "test") == Data("TEST-KEY-one".utf8))
        #expect(try other.read(account: "test") == nil)
        try store.write(Data("TEST-KEY-two".utf8), account: "test")
        #expect(try store.read(account: "test") == Data("TEST-KEY-two".utf8))
        try store.delete(account: "test")
        #expect(try store.read(account: "test") == nil)
        try store.delete(account: "test")
    }

    @Test func signsGooglePKCS8WithSecurityFramework() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let publicKey = try #require(SecKeyCopyPublicKey(key))
        let raw = try #require(SecKeyCopyExternalRepresentation(key, nil) as Data?)
        let algorithm = Data([0x30, 0x0D, 0x06, 0x09] + PEM.rsaEncryptionOID + [0x05, 0x00])
        let pkcs8 = der(0x30, Data([0x02, 0x01, 0x00]) + algorithm + der(0x04, raw))
        let message = Data("test-header.test-claims".utf8)
        for (label, bytes) in [("PRIVATE KEY", pkcs8), ("RSA PRIVATE KEY", raw)] {
            let pem = "-----BEGIN \(label)-----\n\(bytes.base64EncodedString())\n-----END \(label)-----"
            let signature = try SecurityRS256Signer().sign(message, privateKeyPEM: pem)
            #expect(SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                         message as CFData, signature as CFData, nil))
            #expect(!SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                          Data("tampered".utf8) as CFData, signature as CFData, nil))
        }
    }

    @Test func invalidSigningKeyIsRedacted() {
        #expect(throws: SpendError.invalidKey) {
            try SecurityRS256Signer().sign(Data(), privateKeyPEM: "TEST-invalid-private-key")
        }
    }

    private func der(_ tag: UInt8, _ body: Data) -> Data {
        let count = body.count
        let length: [UInt8] = count < 128 ? [UInt8(count)] : [0x82, UInt8(count >> 8), UInt8(count & 0xFF)]
        return Data([tag] + length) + body
    }
}
#endif
