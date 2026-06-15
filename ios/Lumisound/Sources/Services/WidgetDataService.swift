import Foundation
import UIKit
import WidgetKit

/// Writes current-track data to the shared App Group so the WidgetKit extension can
/// read it, then triggers a widget timeline reload. Must be called on @MainActor.
@MainActor
final class WidgetDataService {
    static let shared = WidgetDataService()

    private let appGroupID = "group.com.lumisound.ios"
    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Tracks the last time `reloadAllTimelines()` was fired.
    /// Throttles reloads to at most once every 2 seconds to avoid redundant
    /// WidgetKit refreshes when track changes and play-state changes overlap.
    private var lastReloadTime: Date = .distantPast

    /// Set once the first time `defaults`/the App Group container is found to be
    /// unavailable, so a single warning is logged rather than one per update —
    /// this would otherwise indicate every widget on the device is permanently
    /// stuck on its placeholder ("Nothing Playing") because the host app and the
    /// widget extension aren't sharing the App Group container (e.g. a signing/
    /// provisioning mismatch on a sideloaded build).
    private var loggedMissingAppGroup = false

    private init() {}

    /// Full update: writes track metadata, play state, playback position, and
    /// artwork (if available). Called when the current song changes and artwork
    /// has been loaded, and on play/pause so the widget's live progress display
    /// (`Text(timerInterval:)`) has an accurate anchor.
    func update(song: Song?, isPlaying: Bool, artwork: UIImage?, position: TimeInterval = 0, duration: TimeInterval = 0) {
        guard let ud = defaults else {
            logMissingAppGroupOnce()
            return
        }
        ud.set(song?.displayName ?? "", forKey: "widget_track_title")
        ud.set(song?.artistName ?? "", forKey: "widget_track_artist")
        ud.set(isPlaying, forKey: "widget_is_playing")
        ud.set(position, forKey: "widget_position")
        ud.set(duration, forKey: "widget_duration")
        ud.set(Date().timeIntervalSinceReferenceDate, forKey: "widget_anchor_date")

        if let artwork,
           let data = artwork.jpegData(compressionQuality: 0.85),
           let container = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: appGroupID
           ) {
            let artPath = container.appendingPathComponent("widget_artwork.jpg")
            do {
                try data.write(to: artPath, options: .atomic)
                // Store only the filename so the path stays valid after backup/restore.
                ud.set("widget_artwork.jpg", forKey: "widget_artwork_path")
            } catch {
                appWarn("WidgetDataService: failed to write artwork: \(error.localizedDescription)", category: "widget")
            }
        } else {
            // No artwork for the current song (or no song at all) — clear the
            // stored path so the widget doesn't keep showing the *previous*
            // track's artwork next to the new track's title/artist.
            ud.removeObject(forKey: "widget_artwork_path")
            if let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupID
            ) {
                try? FileManager.default.removeItem(at: container.appendingPathComponent("widget_artwork.jpg"))
            }
        }

        appLog("WidgetDataService: pushed \"\(song?.displayName ?? "nil")\" (playing=\(isPlaying))", category: "widget")
        reloadTimelinesThrottled()
    }

    /// Lightweight update: writes the play/pause state plus the current
    /// position/duration (so the widget's progress anchor stays accurate when
    /// the user pauses/resumes without changing tracks), and reloads timelines.
    func updatePlayState(isPlaying: Bool, position: TimeInterval = 0, duration: TimeInterval = 0) {
        guard let ud = defaults else {
            logMissingAppGroupOnce()
            return
        }
        ud.set(isPlaying, forKey: "widget_is_playing")
        ud.set(position, forKey: "widget_position")
        ud.set(duration, forKey: "widget_duration")
        ud.set(Date().timeIntervalSinceReferenceDate, forKey: "widget_anchor_date")
        reloadTimelinesThrottled()
    }

    // MARK: - Private Helpers

    private func logMissingAppGroupOnce() {
        guard !loggedMissingAppGroup else { return }
        loggedMissingAppGroup = true
        appError("WidgetDataService: App Group '\(appGroupID)' is unavailable — widgets will be stuck on their placeholder", category: "widget")
    }

    /// Calls `WidgetCenter.shared.reloadAllTimelines()` at most once every 2 seconds.
    private func reloadTimelinesThrottled() {
        guard Date().timeIntervalSince(lastReloadTime) >= 2.0 else { return }
        lastReloadTime = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
