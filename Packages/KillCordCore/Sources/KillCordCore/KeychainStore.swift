#if canImport(Security)
import Foundation
import Security

/// Provider keys in the login Keychain, as generic passwords under `Brand.keychainService`. The login
/// keychain isn't synced to iCloud, and `security delete-generic-password -s <service>` removes the items,
/// which the uninstall steps rely on.
public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = Brand.keychainService) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func read(account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw SecretStoreError.keychain(status)
        }
    }

    public func write(_ data: Data, account: String, label: String?) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: label ?? "\(Brand.name): \(ProviderID(rawValue: account)?.info.name ?? account)"
        ]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query(account).merging(attributes) { $1 } as CFDictionary, nil)
            guard added == errSecSuccess else { throw SecretStoreError.keychain(added) }
        } else if status != errSecSuccess {
            throw SecretStoreError.keychain(status)
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }
}
#endif
