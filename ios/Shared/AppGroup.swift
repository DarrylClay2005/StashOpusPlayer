import Foundation
import Security

/// Resolves the App Group container identifier this process was *actually*
/// signed with, instead of assuming the literal `group.com.lumisound.ios`.
///
/// Xcode's automatic signing with a free/personal Apple ID (the norm for
/// SideStore/AltStore sideloads, since a paid Apple Developer Program
/// membership isn't required for it) can't reserve that literal App Group ID
/// globally, so Apple silently suffixes it with the team identifier (e.g.
/// `group.com.lumisound.ios.2HB39W9VS3`) when the profile is generated. The
/// app, widget, and watch targets are all resigned together and so all
/// receive the *same* suffix — but code that hardcodes the unsuffixed
/// literal ends up asking `UserDefaults`/`FileManager` for a suite name that
/// doesn't match what was actually granted, which is why widgets silently
/// stay on their placeholder on sideloaded builds even though the
/// entitlement is present. Reading the grant back from this process's own
/// code-signing entitlements keeps every target in sync automatically,
/// regardless of who signed the build or which suffix (if any) they used.
enum AppGroup {
    /// Used if entitlement self-inspection fails outright (shouldn't happen
    /// on-device, but keeps things working under e.g. a SwiftUI preview host).
    static let literal = "group.com.lumisound.ios"

    static let id: String = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                  task, "com.apple.security.application-groups" as CFString, nil
              ) as? [String],
              !groups.isEmpty
        else {
            return literal
        }
        return groups.first(where: { $0.hasPrefix(literal) }) ?? groups[0]
    }()
}
