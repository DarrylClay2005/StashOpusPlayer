import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — AcoustID API Key Helpers

    /// Refreshes the masked AcoustID API key status from the bridge.
    func refreshAcoustIDKeyStatus() async {
        guard account.isLoggedIn else { return }
        acoustIDKeyConfig = await account.fetchAcoustIDApiKey()
    }

    /// Starts a 5-minute repeating timer that checks whether the user's
    /// YouTube API key has been exposed (e.g. leaked in a public commit/log),
    /// surfacing a warning toast if so. Runs only while Settings is visible.
    func startYouTubeExposureMonitor() {
        guard youtubeExposureTimer == nil else { return }

        // Immediate first check, then repeat every 5 minutes.
        Task { await checkYouTubeKeyExposureAndNotify() }

        let accountService = account
        let timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak accountService] _ in
            guard let accountService else { return }
            Task { @MainActor in
                await SettingsView.checkExposureAndNotify(account: accountService)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        youtubeExposureTimer = timer
    }

    func checkYouTubeKeyExposureAndNotify() async {
        await Self.checkExposureAndNotify(account: account)
    }

    /// Checks for a leaked YouTube API key and shows a warning toast if found.
    /// Takes `account` explicitly so the recurring `Timer` closure can capture
    /// it weakly instead of capturing the whole view.
    @MainActor
    static func checkExposureAndNotify(account: AccountService) async {
        guard account.isLoggedIn else { return }
        let result = await account.checkYouTubeKeyExposure()
        if result.exposed {
            let detail = result.detail.isEmpty
                ? "Your YouTube API key may be publicly exposed."
                : result.detail
            ToastCenter.shared.show(
                "\(detail) Consider regenerating your key in Google Cloud Console.",
                category: .warning,
                icon: "exclamationmark.shield"
            )
        }
    }
}
