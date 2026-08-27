import AppIntents

// MARK: - Lumisound tvOS App Intents / Siri
//
// Reaches the app-wide `TVPlayerModel.shared` (see that type's doc comment
// in TVPlayerView.swift for why it's a real singleton now, not scoped to
// whatever screen is on screen) the same way `TVBridgeClient.shared`/
// `TVAccount.shared` already are. Because `TVPlayerModel` now lives for the
// whole app session rather than only while Now Playing is open, these
// intents can both CONTROL already-playing audio (skip, seek, pause) AND
// START it from cold (`TVPlayFavoritesIntent`) — the latter wasn't
// possible before this file's player-singleton follow-up.
//
// `openAppWhenRun = true`, same reasoning as LumisoundAppIntents.swift on
// iOS: an intent runs outside the normal SwiftUI environment, so the app
// has to actually be brought forward for its state to be safely readable/
// mutable from here (`TVBridgeClient`/`TVAccount` are populated during the
// app's normal launch/login sequence, not before).

enum TVAppIntentError: Error, CustomLocalizedStringResourceConvertible {
    case nothingPlaying
    case notSignedIn
    case noFavorites

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingPlaying:
            return "Nothing is currently playing in Lumisound."
        case .notSignedIn:
            return "Sign in to Lumisound first."
        case .noFavorites:
            return "You don't have any favorite songs yet."
        }
    }
}

struct TVPlayFavoritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Favorites"
    static var description = IntentDescription("Plays your favorite songs in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let client = TVBridgeClient.shared
        guard let token = TVAccount.shared.token else { throw TVAppIntentError.notSignedIn }
        if client.library.isEmpty { await client.fetchLibrary(token: token) }
        if client.favoriteSongIDs.isEmpty { await client.fetchFavorites(token: token) }

        let queue = client.library
            .filter { client.favoriteSongIDs.contains($0.id) }
            .compactMap { client.playable(from: $0, token: token) }
        guard let first = queue.first else { throw TVAppIntentError.noFavorites }

        TVPlayerModel.shared.start(context: TVPlayContext(queue: queue, startID: first.id))
        return .result()
    }
}

struct TVTogglePlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Toggles play/pause in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = TVPlayerModel.shared
        guard !player.queue.isEmpty else { throw TVAppIntentError.nothingPlaying }
        player.togglePlayPause()
        return .result()
    }
}

struct TVSkipToNextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip to Next Track"
    static var description = IntentDescription("Skips to the next track in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = TVPlayerModel.shared
        guard !player.queue.isEmpty else { throw TVAppIntentError.nothingPlaying }
        player.next()
        return .result()
    }
}

struct TVSkipToPreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip to Previous Track"
    static var description = IntentDescription("Skips to the previous track in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = TVPlayerModel.shared
        guard !player.queue.isEmpty else { throw TVAppIntentError.nothingPlaying }
        player.previous()
        return .result()
    }
}

struct TVToggleShuffleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Shuffle"
    static var description = IntentDescription("Toggles shuffle in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = TVPlayerModel.shared
        guard !player.queue.isEmpty else { throw TVAppIntentError.nothingPlaying }
        player.toggleShuffle()
        return .result()
    }
}

struct TVCycleRepeatModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Cycle Repeat Mode"
    static var description = IntentDescription("Cycles Lumisound's repeat mode between off, repeat-all, and repeat-one.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = TVPlayerModel.shared
        guard !player.queue.isEmpty else { throw TVAppIntentError.nothingPlaying }
        player.cycleRepeatMode()
        return .result()
    }
}

/// "Siri, skip forward 30 seconds in Lumisound" / "Siri, skip forward 2
/// minutes in Lumisound" — `Measurement<UnitDuration>` lets Siri parse
/// either unit naturally out of the spoken phrase instead of needing a
/// separate intent per unit.
struct TVSkipForwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Forward"
    static var description = IntentDescription("Skips forward in the current track in Lumisound.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Duration", default: Measurement(value: 15, unit: UnitDuration.seconds))
    var duration: Measurement<UnitDuration>

    static var parameterSummary: some ParameterSummary {
        Summary("Skip forward \(\.$duration) in Lumisound")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = TVPlayerModel.shared
        guard !player.queue.isEmpty else { throw TVAppIntentError.nothingPlaying }
        player.seek(to: player.position + duration.converted(to: .seconds).value)
        return .result()
    }
}

struct TVSkipBackwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Backward"
    static var description = IntentDescription("Skips backward (rewinds) in the current track in Lumisound.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Duration", default: Measurement(value: 15, unit: UnitDuration.seconds))
    var duration: Measurement<UnitDuration>

    static var parameterSummary: some ParameterSummary {
        Summary("Skip backward \(\.$duration) in Lumisound")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let player = TVPlayerModel.shared
        guard !player.queue.isEmpty else { throw TVAppIntentError.nothingPlaying }
        player.seek(to: player.position - duration.converted(to: .seconds).value)
        return .result()
    }
}

struct LumisoundTVShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TVPlayFavoritesIntent(),
            phrases: [
                "Play my favorites in \(.applicationName)",
                "Play favorites in \(.applicationName)",
            ],
            shortTitle: "Play Favorites",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: TVTogglePlayPauseIntent(),
            phrases: ["Toggle playback in \(.applicationName)"],
            shortTitle: "Play/Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: TVSkipToNextTrackIntent(),
            phrases: [
                "Skip to the next track in \(.applicationName)",
                "Play the next song in \(.applicationName)",
            ],
            shortTitle: "Next Track",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: TVSkipToPreviousTrackIntent(),
            phrases: [
                "Skip to the previous track in \(.applicationName)",
                "Play the previous song in \(.applicationName)",
            ],
            shortTitle: "Previous Track",
            systemImageName: "backward.fill"
        )
        AppShortcut(
            intent: TVToggleShuffleIntent(),
            phrases: ["Toggle shuffle in \(.applicationName)"],
            shortTitle: "Toggle Shuffle",
            systemImageName: "shuffle"
        )
        AppShortcut(
            intent: TVCycleRepeatModeIntent(),
            phrases: ["Cycle repeat mode in \(.applicationName)"],
            shortTitle: "Repeat Mode",
            systemImageName: "repeat"
        )
        AppShortcut(
            intent: TVSkipForwardIntent(),
            phrases: [
                "Skip forward \(\.$duration) in \(.applicationName)",
                "Fast forward \(\.$duration) in \(.applicationName)",
            ],
            shortTitle: "Skip Forward",
            systemImageName: "goforward"
        )
        AppShortcut(
            intent: TVSkipBackwardIntent(),
            phrases: [
                "Skip backward \(\.$duration) in \(.applicationName)",
                "Rewind \(\.$duration) in \(.applicationName)",
            ],
            shortTitle: "Skip Backward",
            systemImageName: "gobackward"
        )
    }
}
