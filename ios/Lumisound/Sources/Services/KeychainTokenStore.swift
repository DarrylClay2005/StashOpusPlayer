import Foundation
import Security

// MARK: - KeychainTokenStore
//
// Security hardening pass — the account auth token used to live in plain
// UserDefaults (`Self.tokenKey` in AccountService), which on iOS is an
// unencrypted plist under the app's Documents-adjacent container: readable
// by anything with filesystem access (a jailbreak, a stolen unencrypted
// backup opened on a computer, certain forensic/backup-extraction tools),
// with no OS-level protection at all. The iOS Keychain is the correct home
// for this: hardware-backed encryption on every device with a Secure
// Enclave, and — with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` below —
// inaccessible before the device's first unlock after boot AND excluded
// from ever restoring onto a DIFFERENT device via an iCloud/iTunes backup
// (a lost/sold phone's backup restored elsewhere can't silently resurrect
// this account's session).
//
// A minimal, dependency-free wrapper around the Keychain Services C API
// rather than pulling in a third-party library for one string value —
// `get`/`set`/`delete` are the only operations this ever needs. Takes an
// `account` identifier per call so it can back more than one credential
// (the main account session token, the legacy self-hosted-bridge API key)
// as separate Keychain items under the same app service namespace, rather
// than needing a near-duplicate type per credential.
enum KeychainTokenStore {
    private static let service = "com.lumisound.ios.account"

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
        var query = baseQuery(account: account)

        // Try an update first — SecItemAdd on an already-existing item
        // fails with errSecDuplicateItem rather than overwriting it, so a
        // token refresh has to update in place, not blindly re-add.
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
