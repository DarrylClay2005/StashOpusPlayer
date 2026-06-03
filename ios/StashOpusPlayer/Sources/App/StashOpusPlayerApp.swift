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
    @StateObject private var account = AccountService()

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
                .environmentObject(account)
                .preferredColorScheme(.dark)
                .task {
                    // Restore audio settings — player must be configured before any resume.
                    player.audioSettings = PersistenceService.shared.loadAudioSettings() ?? AudioSettings()

                    // Scan previously added watched folders.
                    libraryManager.scanWatchedFolders(using: folderService)

                    // If logged in, pull latest state from DB as primary storage source.
                    if account.isLoggedIn {
                        await account.pullSync(library: libraryManager)
                    }

                    // Check for updates after a brief delay.
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await updater.checkForUpdates()
                }
                .onAppear {
                    bgService.loadSettings()
                    if bgService.isEnabled, !bgService.images.isEmpty {
                        bgService.startShuffling()
                    }
                }
                // DB as primary storage: push to server whenever favorites or playlists change.
                .onChange(of: libraryManager.favoriteSongIDs) { _ in
                    guard account.isLoggedIn else { return }
                    Task { await account.pushSync(library: libraryManager) }
                }
                .onChange(of: libraryManager.playlists) { _ in
                    guard account.isLoggedIn else { return }
                    Task { await account.pushSync(library: libraryManager) }
                }
                // Persist audio settings to both local and DB when they change.
                .onChange(of: player.audioSettings) { newSettings in
                    PersistenceService.shared.saveAudioSettings(newSettings)
                    if account.isLoggedIn {
                        Task { await account.pushSync(library: libraryManager) }
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
                    if expired { player.pause() }
                }
        }
    }
}
