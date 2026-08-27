import Foundation

// MARK: - AriaCloudCleanupService
//
// Aria Lumi's cloud-library counterpart to `CorruptFileFinderService`'s
// local auto-delete — she already has access to everything in the user's
// cloud music library (`/user/music`), not just what's downloaded to this
// device, so her housekeeping shouldn't stop at the device boundary. Once
// a day, asks the bridge to remove any cloud library entry that never had
// real audio behind it (a failed/partial upload), then surfaces what she
// did the same way her other autonomous actions do — see
// `AccountService.ariaCloudCleanup` for the exact bar and why this one
// skips the local trash-first contract.
@MainActor
enum AriaCloudCleanupService {
    private static let lastRunKey = "ariaCloudCleanup.lastRun"
    private static let interval: TimeInterval = 24 * 60 * 60

    static func runIfNeeded() async {
        let lastRun = UserDefaults.standard.double(forKey: lastRunKey)
        guard Date().timeIntervalSince1970 - lastRun >= interval else { return }
        guard let account = AccountService.shared, account.isLoggedIn else { return }

        let removed = await account.ariaCloudCleanup()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRunKey)
        guard !removed.isEmpty else { return }

        AriaActivityLog.shared.logCloudTracksRemoved(removed)
        appLog("AriaCloudCleanupService: removed \(removed.count) broken cloud entr\(removed.count == 1 ? "y" : "ies")", category: "library")
        RemoteLogger.log(category: "library", event: "aria_cloud_cleanup", detail: ["removed": removed.count])
    }
}
