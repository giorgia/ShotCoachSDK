import Foundation
import Security

/// Static helper to store, retrieve, and delete string values from the system Keychain.
/// Values are never logged — only the key name appears in diagnostic messages.
public struct SCKeychainService: Sendable {

    private init() {}

    // MARK: - Public API

    /// Persists `value` under `key` using kSecClassGenericPassword.
    /// Overwrites any existing entry for the same key.
    /// - Returns: `true` on success.
    @discardableResult
    public static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // Delete first so SecItemAdd always succeeds (update is more complex).
        delete(key: key)

        let query: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrAccount:    key,
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            // Log key name only — never the value.
            print("[SCKeychainService] save failed for key '\(key)', OSStatus=\(status)")
        }
        return status == errSecSuccess
    }

    /// Returns the string stored under `key`, or `nil` if no entry exists.
    public static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData:  kCFBooleanTrue as Any,
            kSecMatchLimit:  kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            if status != errSecItemNotFound {
                print("[SCKeychainService] load failed for key '\(key)', OSStatus=\(status)")
            }
            return nil
        }
        return string
    }

    /// Removes the entry stored under `key`. Safe to call when no entry exists.
    /// - Returns: `true` on success or when the item was not present.
    @discardableResult
    public static func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print("[SCKeychainService] delete failed for key '\(key)', OSStatus=\(status)")
            return false
        }
        return true
    }
}
