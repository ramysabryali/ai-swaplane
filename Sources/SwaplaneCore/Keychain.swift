import Foundation
import Security

/// Abstraction over the macOS Keychain (generic passwords) so tests never touch the real one.
public protocol KeychainClient: Sendable {
    /// Existence check that never reads the secret (avoids access prompts).
    func exists(service: String, account: String?) throws -> Bool
    func read(service: String, account: String?) throws -> Data?
    /// Add-or-update. With `account == nil`, updates the existing item's account, else uses the user name.
    func write(service: String, account: String?, data: Data) throws
    func delete(service: String, account: String?) throws
}

/// Real implementation backed by `SecItem*`.
///
/// Items created by Swaplane are `WhenUnlockedThisDeviceOnly` and non-synchronizable.
/// v0.1 uses the login keychain (the data-protection keychain needs entitlements that an
/// unsigned dev build lacks; revisit at signing time).
public struct SystemKeychain: KeychainClient {
    public init() {}

    private func base(_ service: String, _ account: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account { q[kSecAttrAccount as String] = account }
        return q
    }

    public func exists(service: String, account: String?) throws -> Bool {
        var q = base(service, account)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        if s == errSecSuccess { return true }
        if s == errSecItemNotFound { return false }
        throw SwaplaneError.keychain(s)
    }

    public func read(service: String, account: String?) throws -> Data? {
        var q = base(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess, let data = out as? Data else { throw SwaplaneError.keychain(s) }
        return data
    }

    private func existingAccount(service: String) throws -> String? {
        var q = base(service, nil)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &out)
        if s == errSecItemNotFound { return nil }
        guard s == errSecSuccess, let attrs = out as? [String: Any] else {
            throw SwaplaneError.keychain(s)
        }
        return attrs[kSecAttrAccount as String] as? String
    }

    public func write(service: String, account: String?, data: Data) throws {
        let acct = try account ?? existingAccount(service: service) ?? NSUserName()
        let q = base(service, acct)
        let upd = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if upd == errSecSuccess { return }
        guard upd == errSecItemNotFound else { throw SwaplaneError.keychain(upd) }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        let s = SecItemAdd(add as CFDictionary, nil)
        guard s == errSecSuccess else { throw SwaplaneError.keychain(s) }
    }

    public func delete(service: String, account: String?) throws {
        let s = SecItemDelete(base(service, account) as CFDictionary)
        guard s == errSecSuccess || s == errSecItemNotFound else { throw SwaplaneError.keychain(s) }
    }
}
