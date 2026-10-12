import Foundation
import Security

/// Small key-value store for secrets.
public protocol SecureStore: Sendable {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, for account: String) throws
    func delete(_ account: String) throws
}

public extension SecureStore {
    func readCodable<T: Decodable>(_ type: T.Type, _ account: String) throws -> T? {
        guard let data = try read(account) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func writeCodable<T: Encodable>(_ value: T, for account: String) throws {
        try write(JSONEncoder().encode(value), for: account)
    }
}

public struct KeychainError: Error, CustomStringConvertible {
    public let status: OSStatus
    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        return "Keychain error \(status): \(message)"
    }
}

/// Keychain-backed store. Items are bound to this device (`ThisDeviceOnly`): they are not
/// synced to iCloud and are not restored to another device from a backup.
public struct KeychainStore: SecureStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func read(_ account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = withKeychainFallback(&query) { SecItemCopyMatching($0 as CFDictionary, &result) }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    public func write(_ data: Data, for account: String) throws {
        try delete(account)
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = withKeychainFallback(&query) { SecItemAdd($0 as CFDictionary, nil) }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(_ account: String) throws {
        var query = baseQuery(account)
        let status = withKeychainFallback(&query) { SecItemDelete($0 as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    /// On macOS the data-protection keychain requires a signed app with a team ID. Builds signed
    /// to run locally get errSecMissingEntitlement, so those fall back to the login keychain.
    private func withKeychainFallback(_ query: inout [String: Any], _ operation: ([String: Any]) -> OSStatus) -> OSStatus {
        let status = operation(query)
        #if os(macOS)
        if status == errSecMissingEntitlement {
            query.removeValue(forKey: kSecUseDataProtectionKeychain as String)
            return operation(query)
        }
        #endif
        return status
    }
}

/// In-memory store, used by tests and previews.
public final class MemoryStore: SecureStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    public init() {}

    public func read(_ account: String) throws -> Data? {
        lock.withLock { items[account] }
    }

    public func write(_ data: Data, for account: String) throws {
        lock.withLock { items[account] = data }
    }

    public func delete(_ account: String) throws {
        lock.withLock { _ = items.removeValue(forKey: account) }
    }
}
