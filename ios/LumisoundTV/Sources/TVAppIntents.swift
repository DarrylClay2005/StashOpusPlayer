import AppIntents

// MARK: - Lumisound tvOS App Intents / Siri
//
// Controls whatever's already playing via the Siri Remote's mic button or
// "Hey Siri" (HomePod-paired Apple TVs) — reaches the live `TVPlayerModel`
// through its `.shared` weak singleton (see that type's doc comment in
// TVPlayerView.swift for why a weak pointer, not a real app-wide singleton
// the way iOS's `AudioPlayerManager.shared` is).
//
// That's also this file's real scope limit: `TVPlayerModel` only exists
// while the Now Playing screen is actually on screen (it's a plain
// `@StateObject`, torn down once that view isn't), so unlike iOS these
// intents can only ever CONTROL an already-started session, not START one
// from cold — `TVAppIntentError.nothingPlaying` covers that case with an
// honest error instead of silently no-op'ing or crashing. Starting
// playback from Siri on tvOS would need `TVPlayerModel` promoted to a real
// app-wide singleton first (constructed once at launch, not per-screen),
// which is a genuine architecture change outside this file's scope.
//
// `openAppWhenRun = true`, same reasoning as LumisoundAppIntents.swift on
// iOS: an intent runs outside the normal SwiftUI environment, so the app
// has to actually be brought forward for `.shared` to have any chance of
// being populated.

enum TVAppIntentError: Error, CustomLocalizedStringResourceConvertible {
    case nothingPlaying

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingPlaying:
            return "Nothing is currently playing in Lumisound — open Now Playing first."
        }
    }
}

struct TVTogglePlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Toggles play/pause in Lumisound.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let player = TVPlayerModel.shared else { throw TVAppIntentError.nothingPlaying }
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
        guard let player = TVPlayerModel.shared else { throw TVAppIntentError.nothingPlaying }
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
        guard let player = TVPlayerModel.shared else { throw TVAppIntentError.nothingPlaying }
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
        guard let player = TVPlayerModel.shared else { throw TVAppIntentError.nothingPlaying }
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
        guard let player = TVPlayerModel.shared else { throw TVAppIntentError.nothingPlaying }
        player.cycleRepeatMode()
        return .result()
    }
}

struct LumisoundTVShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
    }
}
