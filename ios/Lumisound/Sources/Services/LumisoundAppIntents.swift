import AppIntents

// MARK: - Lumisound App Intents / Siri Shortcuts
//
// Entirely on-device voice/Shortcuts control — no server round-trip. Each
// intent reaches the live `AudioPlayerManager`/`LibraryManager` via their
// `.shared` weak singletons (the same mechanism `BackgroundRefreshService`
// uses, since an App Intent — like a BGTask — runs outside the normal
// SwiftUI environment and has no other way to reach app state).
//
// `openAppWhenRun = true` is deliberate: these singletons are only populated
// once the app's SwiftUI root has actually constructed its `@StateObject`s
// for this launch. If iOS ran the intent in a lightweight background
// context without doing that, `.shared` would be nil. Forcing the app to
// open guarantees the normal launch sequence has happened first — the
// tradeoff is the app visibly comes to the foreground rather than acting
// silently in the background, which matches how most third-party media
// app Shortcuts already behave.

enum LumisoundIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case noFavorites
    case playlistNotFound
    case emptyPlaylist
    case noSearchResults

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            return "Lumisound needs to finish loading — please try again in a moment."
        case .noFavorites:
            return "You don't have any favorite songs yet."
        case .playlistNotFound:
            return "That playlist couldn't be found — it may have been deleted or renamed."
        case .emptyPlaylist:
            return "That playlist doesn't have any songs yet."
        case .noSearchResults:
            return "Couldn't find anything to play for that search."
        }
    }
}

struct PlayFavoritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Favorites"
    static var description = IntentDescription("Plays your favorite songs in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let library = LibraryManager.shared, let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        let favorites = library.favoriteSongs
        guard !favorites.isEmpty else {
            throw LumisoundIntentError.noFavorites
        }
        player.setQueue(favorites, startIndex: 0, autoplay: true)
        return .result()
    }
}

struct TogglePlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Toggles play/pause in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        player.togglePlayPause()
        return .result()
    }
}

struct SkipToNextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip to Next Track"
    static var description = IntentDescription("Skips to the next track in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        player.skipToNext()
        return .result()
    }
}

struct SkipToPreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip to Previous Track"
    static var description = IntentDescription("Skips to the previous track in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        player.skipToPrevious()
        return .result()
    }
}

struct ToggleShuffleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Shuffle"
    static var description = IntentDescription("Toggles shuffle in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        player.toggleShuffle()
        return .result()
    }
}

/// "Siri, skip forward 30 seconds in Lumisound" — a plain `Int` (seconds).
/// `Measurement<UnitDuration>` was tried twice (once blocked by an old
/// deployment target, once by an unparseable literal default) and even
/// once BOTH of those were fixed, still failed the archive on its own —
/// isolated by confirming this Xcode 26.6 toolchain's
/// `appintentsmetadataprocessor` rejects `Measurement` as an `@Parameter`
/// type outright ("Invalid parameter type. AppEntity and AppEnum are the
/// only allowed types"), on a required parameter with no default,
/// identically on both iOS and tvOS. Whatever the cause (toolchain bug or
/// genuinely unsupported), `Int` is unambiguously a supported primitive
/// parameter type and Siri still resolves a spoken duration into it fine
/// — it just always lands in seconds rather than letting the user name a
/// unit.
struct SeekForwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Forward"
    static var description = IntentDescription("Skips forward in the current track in Lumisound.")
    static var openAppWhenRun: Bool = true

    // Named uniquely (not `seconds`, which `SeekBackwardIntent` below also
    // used to declare) — the previous "Invalid parameter type. AppEntity
    // and AppEnum are the only allowed types" failure, which survived
    // every actual type change tried (Measurement, then Int), turned out
    // to track this instead: two sibling AppIntents in the same file both
    // declaring a same-named @Parameter apparently confuses this Xcode
    // 26.6 toolchain's appintentsmetadataprocessor into misreporting a
    // bogus type error rather than a naming-collision one.
    @Parameter(title: "Seconds", default: 15)
    var forwardSeconds: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Skip forward \(\.$forwardSeconds) seconds in Lumisound")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        player.seek(to: player.position + TimeInterval(forwardSeconds))
        return .result()
    }
}

struct SeekBackwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Backward"
    static var description = IntentDescription("Skips backward (rewinds) in the current track in Lumisound.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Seconds", default: 15)
    var backwardSeconds: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Skip backward \(\.$backwardSeconds) seconds in Lumisound")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        player.seek(to: player.position - TimeInterval(backwardSeconds))
        return .result()
    }
}

struct CycleRepeatModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle Repeat Mode"
    static var description = IntentDescription("Cycles Lumisound's repeat mode between off, repeat-all, and repeat-one.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        player.cycleRepeatMode()
        return .result()
    }
}

/// Lets Siri/Shortcuts start a sleep timer without opening the app first (it
/// still foregrounds the app per `openAppWhenRun`'s doc above, since
/// `SleepTimerService.shared` only exists once the app's normal launch
/// sequence has run — same constraint as every other intent in this file).
struct StartSleepTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Sleep Timer"
    static var description = IntentDescription("Starts Lumisound's sleep timer for a number of minutes.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Minutes", default: 30)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes)-minute sleep timer")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let sleepTimer = SleepTimerService.shared else {
            throw LumisoundIntentError.appNotReady
        }
        let clampedMinutes = min(max(minutes, 1), 240)
        sleepTimer.start(duration: TimeInterval(clampedMinutes * 60))
        return .result()
    }
}

/// An `AppEntity` wrapper around `Playlist` so Siri/Shortcuts can offer the
/// user's playlists by name as a pickable parameter (with autocomplete/
/// disambiguation handled by the system from `PlaylistEntityQuery` below).
struct PlaylistEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Playlist"
    static var defaultQuery = PlaylistEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PlaylistEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    private func allPlaylists() -> [Playlist] {
        LibraryManager.shared?.playlists ?? []
    }

    func entities(for identifiers: [UUID]) async throws -> [PlaylistEntity] {
        await MainActor.run {
            allPlaylists()
                .filter { identifiers.contains($0.id) }
                .map { PlaylistEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [PlaylistEntity] {
        await MainActor.run {
            allPlaylists().map { PlaylistEntity(id: $0.id, name: $0.name) }
        }
    }

    func entities(matching string: String) async throws -> [PlaylistEntity] {
        await MainActor.run {
            allPlaylists()
                .filter { $0.name.localizedCaseInsensitiveContains(string) }
                .map { PlaylistEntity(id: $0.id, name: $0.name) }
        }
    }
}

struct PlayPlaylistIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Playlist"
    static var description = IntentDescription("Plays one of your playlists in Lumisound.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Playlist")
    var playlist: PlaylistEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$playlist) in Lumisound")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let library = LibraryManager.shared, let player = AudioPlayerManager.shared else {
            throw LumisoundIntentError.appNotReady
        }
        guard let match = library.playlists.first(where: { $0.id == playlist.id }) else {
            throw LumisoundIntentError.playlistNotFound
        }
        let songs = library.songs(for: match)
        guard !songs.isEmpty else {
            throw LumisoundIntentError.emptyPlaylist
        }
        player.setQueue(songs, startIndex: 0, autoplay: true)
        return .result()
    }
}

/// Searches the streaming bridge (YouTube by default) for *query* and plays the
/// best match, queuing a few more related results as Up Next — mirrors the
/// Auto-Radio seeding pattern in `LumisoundApp.swift` (which calls
/// `relatedTracks` rather than `search(query:source:)` specifically so it
/// doesn't clobber the published `searchResults` state the Stream Search tab's
/// UI is bound to; this intent has the exact same requirement, since the app
/// is being foregrounded and the user may already have a search in progress).
struct SearchAndPlayIntent: AppIntent {
    static var title: LocalizedStringResource = "Search and Play"
    static var description = IntentDescription("Searches and plays a song in Lumisound.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Search")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$query) in Lumisound")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = AudioPlayerManager.shared, let streaming = StreamingService.shared else {
            throw LumisoundIntentError.appNotReady
        }
        let tracks = await streaming.relatedTracks(query: query, source: "youtube", limit: 5)
        guard !tracks.isEmpty else {
            throw LumisoundIntentError.noSearchResults
        }
        var songs: [Song] = []
        for track in tracks {
            guard let url = try? await streaming.streamURL(for: track) else { continue }
            songs.append(streaming.toSong(track: track, streamURL: url))
        }
        guard !songs.isEmpty else {
            throw LumisoundIntentError.noSearchResults
        }
        player.setQueue(songs, startIndex: 0, autoplay: true)
        return .result()
    }
}

struct LumisoundShortcuts: AppShortcutsProvider {
    // Apple caps AppShortcutsProvider at 10 entries per app — exceeding it
    // fails the archive outright ("Found 11 App Shortcuts, but each app may
    // have at most 10"), and the metadata processor's OTHER diagnostics
    // from the same failed export (bogus-looking "Invalid parameter type"
    // errors on otherwise perfectly valid parameters) are a confusing,
    // misleading side effect of that overflow, not real problems with those
    // parameters. ToggleShuffleIntent/CycleRepeatModeIntent are still fully
    // functional intents (usable from the Shortcuts app), just no longer
    // pre-registered with a default Siri phrase — traded for the two new
    // seek intents below, which are more likely to actually get spoken.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayFavoritesIntent(),
            phrases: [
                "Play my favorites in \(.applicationName)",
                "Play favorites in \(.applicationName)",
            ],
            shortTitle: "Play Favorites",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: TogglePlayPauseIntent(),
            phrases: ["Toggle playback in \(.applicationName)"],
            shortTitle: "Play/Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: SkipToNextTrackIntent(),
            phrases: [
                "Skip to the next track in \(.applicationName)",
                "Play the next song in \(.applicationName)",
            ],
            shortTitle: "Next Track",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: SkipToPreviousTrackIntent(),
            phrases: [
                "Skip to the previous track in \(.applicationName)",
                "Play the previous song in \(.applicationName)",
            ],
            shortTitle: "Previous Track",
            systemImageName: "backward.fill"
        )
        AppShortcut(
            intent: SeekForwardIntent(),
            phrases: [
                "Skip forward \(\.$forwardSeconds) seconds in \(.applicationName)",
                "Fast forward \(\.$forwardSeconds) seconds in \(.applicationName)",
            ],
            shortTitle: "Skip Forward",
            systemImageName: "goforward"
        )
        AppShortcut(
            intent: SeekBackwardIntent(),
            phrases: [
                "Skip backward \(\.$backwardSeconds) seconds in \(.applicationName)",
                "Rewind \(\.$backwardSeconds) seconds in \(.applicationName)",
            ],
            shortTitle: "Skip Backward",
            systemImageName: "gobackward"
        )
        AppShortcut(
            intent: StartSleepTimerIntent(),
            phrases: [
                "Start a sleep timer in \(.applicationName)",
                "Set a sleep timer in \(.applicationName)",
            ],
            shortTitle: "Sleep Timer",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: [
                "Play \(\.$playlist) in \(.applicationName)",
                "Play my \(\.$playlist) playlist in \(.applicationName)",
            ],
            shortTitle: "Play Playlist",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: SearchAndPlayIntent(),
            // No `\(\.$query)` interpolation here — only AppEntity/AppEnum
            // parameters can be embedded in a phrase; `query` is a plain
            // `String` (Siri still prompts for it via the intent's own
            // parameter summary when the phrase alone is matched).
            phrases: [
                "Search and play in \(.applicationName)",
                "Play a song in \(.applicationName)",
            ],
            shortTitle: "Search and Play",
            systemImageName: "magnifyingglass"
        )
    }
}
