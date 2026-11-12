import Foundation
import Security

/// Minimal Keychain storage for secrets such as API keys. Values stay on this device.
enum Keychain {
    private static let service = "Stride"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        var attributes = query(account)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
