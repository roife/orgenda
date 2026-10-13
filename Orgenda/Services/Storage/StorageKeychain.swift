import Foundation
import Security

struct StorageCredential: Codable, Sendable {
    var username: String
    var password: String
}

enum StorageKeychain {
    private static let service = "com.roifewu.Orgenda.storage"
    private static let lock = NSLock()

    static func read(_ key: String) throws -> StorageCredential {
        lock.lock(); defer { lock.unlock() }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: key,
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw StorageError.authenticationRequired
        }
        return try JSONDecoder().decode(StorageCredential.self, from: data)
    }

    static func write(_ credential: StorageCredential, key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: key]
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(credential),
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, value in value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw StorageError.authenticationRequired }
        } else if status != errSecSuccess { throw StorageError.authenticationRequired }
    }

    static func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.authenticationRequired }
    }
}
