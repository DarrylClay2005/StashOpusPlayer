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
    @StateObject private var bridgeHealth = BridgeHealthService()

    @State private var showLaunch = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(libraryManager)
                    .environmentObject(player)
                    .environmentObject(sleepTimer)
                    .environmentObject(updater)
                    .environmentObject(streaming)
                    .environmentObject(folderService)
                    .environmentObject(bgService)
                    .environmentObject(account)
                    .environmentObject(bridgeHealth)
                    .opacity(showLaunch ? 0 : 1)

                if showLaunch {
                    LaunchView(isLoading: $showLaunch)
                        .environmentObject(account)
                        .environmentObject(libraryManager)
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                    // Configure background logger
                    AppLogger.shared.configure(bridgeURL: streaming.bridgeURL)
                    AppLogger.shared.log("App launched", category: "app")

                    // Restore audio settings — player must be configured before any resume.
                    player.audioSettings = PersistenceService.shared.loadAudioSettings() ?? AudioSettings()

                    // Scan previously added watched folders.
                    libraryManager.scanWatchedFolders(using: folderService)

                    // If logged in, pull latest state from DB as primary storage source.
                    if account.isLoggedIn {
                        await account.pullSync(library: libraryManager)
                        account.startAutoPushTimer(library: libraryManager)
                        await account.loadAvatar()
                    }

                    // Start periodic bridge health checks.
                    bridgeHealth.startPeriodicChecks(streaming: streaming)

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
                // schedulePush debounces rapid bursts (e.g. initial library scan) into one write.
                .onChange(of: libraryManager.favoriteSongIDs) { _ in
                    account.schedulePush(library: libraryManager)
                }
                .onChange(of: libraryManager.playlists) { _ in
                    account.schedulePush(library: libraryManager)
                }
                // Persist audio settings to local AND DB when they change.
                .onChange(of: player.audioSettings) { newSettings in
                    PersistenceService.shared.saveAudioSettings(newSettings)
                    // Pass audioSettings so the server saves them too
                    account.schedulePush(library: libraryManager, audioSettings: newSettings)
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
                // When the user logs in after launch, start the auto-push timer and load avatar.
                .onReceive(account.$isLoggedIn) { loggedIn in
                    guard loggedIn else {
                        account.stopAutoPushTimer()
                        return
                    }
                    account.startAutoPushTimer(library: libraryManager)
                    Task { await account.loadAvatar() }
                }
        }
    }
}
