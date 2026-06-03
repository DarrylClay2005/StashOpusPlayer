import SwiftUI
import UIKit

@main
struct StashOpusPlayerApp: App {
    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var sleepTimer = SleepTimerService()
    @StateObject private var updater = UpdateService.shared
    @StateObject private var streaming = StreamingService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryManager)
                .environmentObject(player)
                .environmentObject(sleepTimer)
                .environmentObject(updater)
                .environmentObject(streaming)
                .preferredColorScheme(.dark)
                .task {
                    // Restore audio settings first so the player is configured before any resume.
                    player.audioSettings = PersistenceService.shared.loadAudioSettings() ?? AudioSettings()

                    // Check for updates after a brief delay to avoid blocking launch.
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await updater.checkForUpdates()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    PersistenceService.shared.saveAudioSettings(player.audioSettings)
                }
                .onReceive(sleepTimer.$didExpire) { expired in
                    if expired {
                        player.pause()
                    }
                }
        }
    }
}
