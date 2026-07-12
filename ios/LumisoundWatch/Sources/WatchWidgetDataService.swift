import Foundation
import WidgetKit

// MARK: - WatchWidgetDataService
//
// Mirrors the current Now Playing state (whichever source is freshest — the
// phone mirror via WatchConnectivityManager, or standalone playback via
// WatchLocalPlayerManager) into an app-group UserDefaults container so the
// watch complication (a separate WidgetKit extension target — see
// WatchWidget/Sources/LumisoundWatchWidget.swift) can read it with no direct
// dependency between the two targets. Same split as the iOS
// WidgetDataService/LumisoundWidget pair.
//
// IMPORTANT: an iOS app-group container does NOT sync across the
// Bluetooth/WatchConnectivity link to the watch's own app-group container —
// app groups are per-device storage, not a cross-device sync mechanism. This
// is the watch's LOCAL app-group container; it needs its own entitlement
// grant (see project.yml notes in the task report — not added here, since
// this target intentionally doesn't touch project.yml/entitlements).
enum WatchWidgetDataService {
    private static let appGroupID = "group.com.lumisound.ios"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func update(title: String, artist: String, isPlaying: Bool) {
        guard let defaults else { return }
        defaults.set(title, forKey: "watch_widget_title")
        defaults.set(artist, forKey: "watch_widget_artist")
        defaults.set(isPlaying, forKey: "watch_widget_is_playing")
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: "watch_widget_updated_at")
        reloadTimelinesThrottled()
    }

    static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: "watch_widget_title")
        defaults.removeObject(forKey: "watch_widget_artist")
        defaults.set(false, forKey: "watch_widget_is_playing")
        reloadTimelinesThrottled()
    }

    // Same throttle rationale as the iOS WidgetDataService: reloadAllTimelines()
    // is not free and playback updates can fire many times a second (position
    // ticks) — cap actual widget reloads to once per 2 seconds.
    private static var lastReload: Date = .distantPast

    private static func reloadTimelinesThrottled() {
        let now = Date()
        guard now.timeIntervalSince(lastReload) > 2 else { return }
        lastReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }
}
