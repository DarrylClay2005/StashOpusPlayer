import SwiftUI
import UIKit

@main
struct StashOpusPlayerApp: App {
    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var sleepTimer = SleepTimerService()
    @StateObject private var updater = UpdateService.shared
    @StateObject private var streaming = StreamingService()
    @StateObject private var folderService = MusicFolderService()
    @StateObject private var bgService = BackgroundService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryManager)
                .environmentObject(player)
                .environmentObject(sleepTimer)
                .environmentObject(updater)
                .environmentObject(streaming)
                .environmentObject(folderService)
                .environmentObject(bgService)
                .preferredColorScheme(.dark)
                .task {
                    // Restore audio settings first so the player is configured before any resume.
                    player.audioSettings = PersistenceService.shared.loadAudioSettings() ?? AudioSettings()

                    // Scan any previously added watched folders at launch.
                    libraryManager.scanWatchedFolders(using: folderService)

                    // Check for updates after a brief delay to avoid blocking launch.
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await updater.checkForUpdates()
                }
                .onAppear {
                    bgService.loadSettings()
                    // loadSettings() resets isEnabled to false if images is empty (not persisted),
                    // so only start shuffling if both conditions are met after loading.
                    if bgService.isEnabled, !bgService.images.isEmpty {
                        bgService.startShuffling()
                    }
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
