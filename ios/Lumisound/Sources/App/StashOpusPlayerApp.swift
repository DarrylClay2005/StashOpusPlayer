import SwiftUI
import UIKit

@main
struct LumisoundApp: App {
    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var player = AudioPlayerManager()
    @StateObject private var sleepTimer = SleepTimerService()
    @StateObject private var updater = UpdateService.shared
    @StateObject private var streaming = StreamingService()
    @StateObject private var folderService = MusicFolderService()
    @StateObject private var bgService = BackgroundService()
    @StateObject private var account = AccountService()
    @StateObject private var bridgeHealth = BridgeHealthService()
    @StateObject private var moodService = MoodPlaylistService()
    @StateObject private var cacheManager = CacheManagerService()

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
                    .environmentObject(moodService)
                    .environmentObject(cacheManager)
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
                    // Configure background logger (idempotent — safe if .task fires multiple times)
                    AppLogger.shared.configure(bridgeURL: streaming.bridgeURL)

                    // Restore audio settings — player must be configured before any resume.
                    player.audioSettings = PersistenceService.shared.loadAudioSettings() ?? AudioSettings()

                    // Wire the sleep-timer fade to the player's volume control.
                    sleepTimer.getVolume = { player.audioSettings.volume }
                    sleepTimer.setVolume = { player.audioSettings.volume = $0 }
                    sleepTimer.onExpire  = { player.pause() }

                    // Wire mood service to library so it can access songs.
                    moodService.libraryManager = libraryManager

                    // Auto-scan for corrupt files once per day (non-blocking).
                    CorruptFileFinderService.shared.runDailyCheckIfNeeded()

                    // Scan previously added watched folders.
                    libraryManager.scanWatchedFolders(using: folderService)

                    // If logged in, pull latest state from DB as primary storage source.
                    if account.isLoggedIn {
                        await account.pullSync(library: libraryManager)
                        account.startAutoPushTimer(library: libraryManager)
                        await account.loadAvatar(forceRefresh: true)
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
                // Auto-Radio: when the queue ends and autoRadioEnabled is on, search YouTube
                // for tracks similar to the last-played song and append them to the queue.
                .onReceive(player.$autoRadioSeed.compactMap { $0 }) { seed in
                    player.clearAutoRadioSeed()
                    guard player.autoRadioEnabled else { return }
                    Task {
                        appLog("Auto-radio: seeding from \"\(seed.displayName)\" by \(seed.artistName)", category: "audio")
                        await streaming.search(
                            query: "\(seed.artistName) \(seed.displayName)",
                            source: "youtube"
                        )
                        let tracks = Array(streaming.searchResults.prefix(5))
                        guard !tracks.isEmpty else {
                            appLog("Auto-radio: no results", category: "audio")
                            return
                        }
                        for track in tracks {
                            guard let url = try? await streaming.streamURL(for: track) else { continue }
                            player.appendToQueue(song: streaming.toSong(track: track, streamURL: url))
                        }
                        if !player.isPlaying { player.skipToNext() }
                        appLog("Auto-radio: appended \(tracks.count) track(s)", category: "audio")
                    }
                }
                // When the user logs in after launch, start the auto-push timer and load avatar.
                .onReceive(account.$isLoggedIn) { loggedIn in
                    guard loggedIn else {
                        account.stopAutoPushTimer()
                        return
                    }
                    account.startAutoPushTimer(library: libraryManager)
                    Task { await account.loadAvatar(forceRefresh: true) }
                }
        }
    }
}
