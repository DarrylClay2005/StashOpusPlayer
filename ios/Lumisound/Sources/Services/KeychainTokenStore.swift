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
// Enclave, and — with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
// below — excluded from ever restoring onto a DIFFERENT device via an
// iCloud/iTunes backup (a lost/sold phone's backup restored elsewhere
// can't silently resurrect this account's session).
//
// Deliberately `AfterFirstUnlock`, NOT `WhenUnlocked`: this app registers
// background tasks (BGAppRefreshTask in BackgroundRefreshService, the
// LumisoundTrackVaultService relock pass) that can run while the device
// screen is locked, and AccountService.init() — which reads this token to
// decide isLoggedIn — runs on every one of those headless launches too.
// `WhenUnlocked` makes the item unreadable any time the screen is merely
// locked (not just before first-unlock-since-boot), so a background launch
// while locked would see a read failure indistinguishable from "no token,"
// flip isLoggedIn to false, and — because SwiftUI reuses the same
// long-lived @StateObject rather than re-running init() on next foreground
// — leave the user looking logged-out the next time they actually open the
// app, even though the real Keychain item and server-side session were
// both untouched. `AfterFirstUnlock` still fully satisfies "never usable
// before the device is unlocked for the first time after a reboot," while
// staying readable for the rest of the device's uptime the way a
// background-readable session token needs to be.
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

        // Delete-then-add rather than update-in-place: SecItemUpdate only
        // touches kSecValueData, not kSecAttrAccessible, so an item written
        // under an older/different accessibility attribute (e.g. an
        // existing install's token, still stored under the old
        // WhenUnlockedThisDeviceOnly value before this fix) would silently
        // keep that old attribute forever if only ever updated in place.
        // Deleting first guarantees every write picks up the current
        // accessibility attribute below, so already-affected devices
        // self-heal the next time this is called (login, token refresh,
        // etc.) without needing a separate one-time migration pass.
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
