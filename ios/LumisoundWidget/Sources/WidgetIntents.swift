import AppIntents
import Foundation
import WidgetKit

// MARK: - Darwin notification names

enum WidgetNotificationNames {
    static let togglePlayback = "com.lumisound.ios.widget.togglePlayback"
    static let skipNext       = "com.lumisound.ios.widget.skipNext"
    static let skipPrevious   = "com.lumisound.ios.widget.skipPrevious"
    static let toggleFavorite = "com.lumisound.ios.widget.toggleFavorite"
}

/// App Group shared with the host app — matches `WidgetDataService`'s
/// `appGroupID` and `LumisoundWidgetProvider`'s `appGroupID`.
private let widgetAppGroupID = AppGroup.id

// MARK: - Toggle Playback

struct TogglePlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Playback"
    static let description = IntentDescription("Play or pause Lumisound.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        postDarwin(name: WidgetNotificationNames.togglePlayback)
        return .result()
    }
}

// MARK: - Skip Previous

struct SkipPreviousIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip to Previous"
    static let description = IntentDescription("Skip to the previous track in Lumisound.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        postDarwin(name: WidgetNotificationNames.skipPrevious)
        return .result()
    }
}

// MARK: - Skip Next

struct SkipNextIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip to Next"
    static let description = IntentDescription("Skip to the next track in Lumisound.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        postDarwin(name: WidgetNotificationNames.skipNext)
        return .result()
    }
}

// MARK: - Toggle Favorite

/// Favorites/unfavorites the currently-playing track from a Home Screen
/// widget button.
///
/// Unlike the transport controls above, this can't be satisfied by the host
/// app alone reacting to a Darwin notification: if `Lumisound` is fully
/// suspended or not running at all, iOS will NOT launch it in the
/// background just because a widget's `AppIntent` ran (that's an
/// intentional widget-extension sandboxing limit, not something
/// `openAppWhenRun` can override without also bringing the app to the
/// foreground, which `TogglePlaybackIntent` et al. deliberately avoid). So
/// this intent does both:
///   1. Flips a standalone `widget_is_favorite` flag directly in the shared
///      App Group and reloads the widget's timeline — an optimistic update
///      that's visible immediately, even with the app fully killed.
///   2. Posts the same Darwin notification the transport controls use, so
///      that if the app process IS alive, `AudioPlayerManager` performs the
///      real toggle via `LibraryManager.toggleFavorite(songID:)` and
///      overwrites this guess with the authoritative value (see
///      `AudioPlayerManager.toggleFavoriteFromWidget()`).
/// If the app was fully killed, this optimistic flag is all the user gets
/// until they next open the app — there is no way to do better from a
/// widget-button intent.
struct ToggleFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Favorite"
    static let description = IntentDescription("Favorites or unfavorites the current track in Lumisound.")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let ud = UserDefaults(suiteName: widgetAppGroupID)
        let newValue = !(ud?.bool(forKey: "widget_is_favorite") ?? false)
        ud?.set(newValue, forKey: "widget_is_favorite")
        WidgetCenter.shared.reloadAllTimelines()

        postDarwin(name: WidgetNotificationNames.toggleFavorite)
        return .result()
    }
}

// MARK: - Darwin post helper

private func postDarwin(name: String) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(name as CFString),
        nil, nil, true
    )
}
