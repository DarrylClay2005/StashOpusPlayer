import Foundation
import Security

/// Resolves the App Group container identifier this process was *actually*
/// signed with, instead of assuming the literal `group.com.lumisound.ios`.
///
/// Free/personal-team signing (the norm for SideStore/AltStore sideloads,
/// since a paid Apple Developer Program membership isn't required for it)
/// can't reserve that literal App Group ID globally, so the signing tool
/// suffixes it with the team identifier instead (e.g.
/// `group.com.lumisound.ios.2HB39W9VS3`) — confirmed from an actual embedded
/// provisioning profile. The app, widget, and watch targets are all resigned
/// together and so all receive the *same* suffix — but code that hardcodes
/// the unsuffixed literal ends up asking `UserDefaults`/`FileManager` for a
/// suite name that doesn't match what was actually granted, which is why
/// widgets silently stay on their placeholder on sideloaded builds even
/// though the entitlement is present.
///
/// `SecTaskCopyValueForEntitlement` (reading our own entitlements directly)
/// isn't part of Security.framework's public Swift module map on iOS, so
/// instead this recovers the team identifier the same way many apps do:
/// iOS tags any keychain item saved without an explicit access group with
/// `"<TeamID>.<bundleID>"`, and `kSecAttrAccessGroup` is documented, public
/// API — so a throwaway keychain probe reveals our own team identifier
/// regardless of how (or by whom) the build was signed.
enum AppGroup {
    static let literal = "group.com.lumisound.ios"

    static let id: String = {
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: literal) != nil {
            return literal
        }
        if let teamID = discoverTeamIdentifier() {
            let suffixed = "\(literal).\(teamID)"
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suffixed) != nil {
                return suffixed
            }
        }
        return literal
    }()

    private static func discoverTeamIdentifier() -> String? {
        let probeQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "AppGroupTeamIdentifierProbe",
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        var status = SecItemCopyMatching(probeQuery as CFDictionary, &result)

        if status == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "AppGroupTeamIdentifierProbe",
                kSecValueData as String: Data(),
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
            status = SecItemCopyMatching(probeQuery as CFDictionary, &result)
        }

        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let accessGroup = attributes[kSecAttrAccessGroup as String] as? String,
              let dotIndex = accessGroup.firstIndex(of: ".")
        else { return nil }

        return String(accessGroup[..<dotIndex])
    }
}
