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

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady:
            return "Lumisound needs to finish loading — please try again in a moment."
        case .noFavorites:
            return "You don't have any favorite songs yet."
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

struct LumisoundShortcuts: AppShortcutsProvider {
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
    }
}
