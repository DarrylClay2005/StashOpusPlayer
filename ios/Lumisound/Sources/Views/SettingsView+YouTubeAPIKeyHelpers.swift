import MediaPlayer
import SwiftUI

extension SettingsView {

    // MARK: — YouTube API Key Helpers

    /// Refreshes the masked YouTube API key status from the bridge.
    func refreshYouTubeKeyStatus() async {
        guard account.isLoggedIn else { return }
        youtubeKeyConfig = await account.fetchYoutubeApiKey()
    }
}
