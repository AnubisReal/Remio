import Foundation
import Security

struct PortalCredential: Codable, Sendable {
    let endpoint: PortalEndpoint
    let name: String
    let token: String
}

protocol PortalSessionStorage: Sendable {
    func load() throws -> PortalCredential?
    func save(_ credential: PortalCredential) throws
    func forget() throws
}

struct KeychainPortalSessionStorage: PortalSessionStorage {
    func load() throws -> PortalCredential? { try PortalVault.load() }
    func save(_ credential: PortalCredential) throws { try PortalVault.save(credential) }
    func forget() throws { try PortalVault.forget() }
}

/// Single-Portal session for the first version. No Safari imports or roster replication.
enum PortalVault {
    private static let service = "com.remio.portal-session"
    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load(account: String = "primary-v1") throws -> PortalCredential? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let credential = try? JSONDecoder().decode(PortalCredential.self, from: data) else { throw PortalError.keychain }
        return credential
    }

    static func save(_ credential: PortalCredential, account: String = "primary-v1") throws {
        let query = query(account: account)
        let data = try JSONEncoder().encode(credential)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PortalError.keychain }
        } else if status != errSecSuccess { throw PortalError.keychain }
    }

    static func forget(account: String = "primary-v1") throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PortalError.keychain }
    }
}
