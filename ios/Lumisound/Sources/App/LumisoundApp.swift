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

    init() {
        // Must happen before the app finishes launching — too late if done
        // from a View's .task/.onAppear. See BackgroundRefreshService's docs
        // for what this actually does (and doesn't) guarantee.
        BackgroundRefreshService.register()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(libraryManager)
                    .environmentObject(player)
                    .environmentObject(player.progress)
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
                    .animation(.easeInOut(duration: 0.4), value: showLaunch)

                if showLaunch {
                    LaunchView(isLoading: $showLaunch)
                        .environmentObject(account)
                        .environmentObject(libraryManager)
                        .environmentObject(player)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: showLaunch)
            .preferredColorScheme(.dark)
            .task {
                    // Configure background logger (idempotent — safe if .task fires multiple times)
                    AppLogger.shared.configure(bridgeURL: streaming.bridgeURL)

                    // Restore audio settings — player must be configured before any resume.
                    player.restoreDefaultAudioSettings(PersistenceService.shared.loadAudioSettings() ?? AudioSettings())

                    // Wire the sleep-timer fade to the player's volume control.
                    sleepTimer.getVolume = { player.audioSettings.volume }
                    sleepTimer.setVolume = { player.audioSettings.volume = $0 }
                    sleepTimer.getRate   = { player.audioSettings.speed }
                    sleepTimer.setRate   = { player.audioSettings.speed = $0 }
                    sleepTimer.onExpire  = { player.pause() }

                    // Wire mood service to library so it can access songs.
                    moodService.libraryManager = libraryManager

                    // Wire player to library so it can resolve track BPM for
                    // beat-aware crossfades.
                    player.libraryManager = libraryManager

                    // Route transport commands from the watch companion to the player.
                    PhoneWatchSync.shared.commandHandler = { command in
                        switch command {
                        case "toggle":   player.togglePlayPause()
                        case "next":     player.skipToNext()
                        case "previous": player.skipToPrevious()
                        default:         break
                        }
                    }

                    // Auto-scan for corrupt files immediately, then every 5 minutes
                    // for the rest of the session (non-blocking, all users).
                    CorruptFileFinderService.shared.startPeriodicScanning()

                    // Periodically retry online metadata lookups for imported
                    // tracks still missing artist/album/genre/year (e.g. after
                    // restoring files from a backup).
                    libraryManager.startPeriodicMetadataReenrichment()

                    // Every 3 minutes, re-read embedded tags for a small rotating
                    // batch of imported tracks so externally-updated metadata
                    // (e.g. a bridge re-tag) surfaces without a full rescan.
                    libraryManager.startPeriodicMetadataRefresh()

                    // Scan previously added watched folders.
                    libraryManager.scanWatchedFolders(using: folderService)

                    // Auto-download new tracks from any tracked playlists that have it
                    // enabled (throttled internally; each playlist does its own fresh
                    // library scan before deciding what's new — see
                    // TrackedPlaylistStore.runAutoDownloads — so it doesn't need to wait
                    // for anything above to finish first). Fired as its own independent
                    // Task rather than awaited in this sequential chain: it used to run
                    // dead last, after account sync, notification-permission prompts,
                    // bridge health checks, a 3s sleep, and a GitHub update check —  a
                    // normal "open the app, glance at it, close it" session routinely got
                    // this whole .task cancelled by view disappearance before ever
                    // reaching that line, so auto-download silently never ran. A plain
                    // Task{} is unstructured — it starts immediately and keeps running
                    // independently of this .task's own cancellation, so it actually gets
                    // a chance to finish even on a quick app open.
                    Task {
                        await TrackedPlaylistStore.shared.runAutoDownloads(
                            streaming: streaming, library: libraryManager
                        )
                    }

                    // If logged in, pull latest state from DB as primary storage source.
                    if account.isLoggedIn {
                        await account.pullSync(library: libraryManager, player: player)
                        account.startAutoPushTimer(library: libraryManager)
                        await account.loadAvatar(forceRefresh: true)
                    }

                    // Push per-track audio settings to the server whenever they change.
                    player.onTrackAudioSettingsChanged = { [weak account, weak libraryManager, weak player] in
                        guard let account, let libraryManager, let player else { return }
                        account.schedulePush(
                            library: libraryManager,
                            audioSettings: player.defaultAudioSettings,
                            trackAudioSettings: player.perTrackAudioSettings
                        )
                    }

                    // Request device-notification authorization and mirror any
                    // existing unread server-inbox items to device notifications.
                    await NotificationService.shared.requestAuthorization()
                    if account.isLoggedIn {
                        let unread = await account.fetchNotifications(unreadOnly: true)
                        NotificationService.shared.syncServerNotifications(unread)
                    }

                    // Start periodic bridge health checks.
                    bridgeHealth.startPeriodicChecks(streaming: streaming)

                    // Check for updates after a brief delay.
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await updater.checkForUpdates()

                    // Queue the periodic background check (subscriptions +
                    // tracked playlists) — see BackgroundRefreshService.
                    BackgroundRefreshService.scheduleNext()
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
                // Persist audio settings to local AND DB when they change. While a
                // per-track override is active, `audioSettings` reflects that
                // track's settings rather than the global default — only persist
                // the latter as the global default (`player.defaultAudioSettings`
                // is unaffected by per-track overrides); the per-track values are
                // persisted separately via `onTrackAudioSettingsChanged` above.
                .onChange(of: player.audioSettings) { newSettings in
                    if player.isUsingTrackAudioSettings {
                        PersistenceService.shared.saveAudioSettings(player.defaultAudioSettings)
                    } else {
                        PersistenceService.shared.saveAudioSettings(newSettings)
                    }
                    account.schedulePush(
                        library: libraryManager,
                        audioSettings: player.defaultAudioSettings,
                        trackAudioSettings: player.perTrackAudioSettings
                    )
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    PersistenceService.shared.saveAudioSettings(player.defaultAudioSettings)
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
                        // BPM-aware query: bias the related-tracks search toward
                        // results that match the seed's tempo feel, so a fast/energetic
                        // seed doesn't get followed by a string of ballads (or vice versa).
                        let seedBPM = await libraryManager.bpm(for: seed)
                        let tempoHint = autoRadioTempoHint(for: seedBPM)
                        let query = [seed.artistName, seed.displayName, tempoHint]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        // Uses `relatedTracks`, not `search` — the latter publishes
                        // into `searchResults`/`isSearching`/`errorMessage`, which
                        // would silently overwrite whatever the user has up in the
                        // Stream Search tab right as their queue runs out.
                        let tracks = await streaming.relatedTracks(
                            query: query,
                            source: "youtube",
                            limit: 5
                        )
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

/// Maps a tempo to a short search-query keyword so Auto-Radio's related-tracks
/// search is biased toward results with a similar energy level as the seed
/// track. Returns `nil` for unknown or "normal"-tempo (90-120 BPM) seeds, where
/// no extra hint is needed — the artist/title alone is descriptive enough.
private func autoRadioTempoHint(for bpm: Double?) -> String? {
    guard let bpm, bpm > 0 else { return nil }
    switch bpm {
    case ..<60:    return "ambient"
    case 60..<90:  return "chill"
    case 90..<120: return nil
    default:       return "energetic"
    }
}
