import Foundation
import Security

// MARK: - TVKeychainTokenStore
//
// tvOS counterpart to the iOS target's KeychainTokenStore — the session JWT
// used to live in plain UserDefaults (TVAccount's `tokenKey`), which is an
// unencrypted plist with no OS-level protection. Moves it to the Keychain
// for the same reasons the iOS target already does: hardware-backed
// encryption, and excluded from ever restoring onto a different Apple TV
// via an iCloud backup with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
//
// Separate service namespace from the iOS store ("com.lumisound.tvos.account")
// even though code-signing keychain-access-group isolation already prevents
// cross-target reads — keeping the identifiers distinct just makes each
// store's scope unambiguous.
enum TVKeychainTokenStore {
    private static let service = "com.lumisound.tvos.account"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete-then-add rather than update-in-place — see the iOS store's
        // identical comment: guarantees every write picks up the current
        // kSecAttrAccessible value rather than being stuck on whatever an
        // older write used.
        SecItemDelete(baseQuery(account: account) as CFDictionary)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
