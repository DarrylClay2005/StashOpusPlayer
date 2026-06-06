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

    private init() {}

    /// Full update: writes track metadata, play state, and artwork (if available).
    /// Called when the current song changes and artwork has been loaded.
    func update(song: Song?, isPlaying: Bool, artwork: UIImage?) {
        guard let ud = defaults else { return }
        ud.set(song?.displayName ?? "", forKey: "widget_track_title")
        ud.set(song?.artistName ?? "", forKey: "widget_track_artist")
        ud.set(isPlaying, forKey: "widget_is_playing")

        if let artwork,
           let data = artwork.jpegData(compressionQuality: 0.85),
           let container = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: appGroupID
           ) {
            let artPath = container.appendingPathComponent("widget_artwork.jpg")
            try? data.write(to: artPath, options: .atomic)
            // Store only the filename so the path stays valid after backup/restore.
            ud.set("widget_artwork.jpg", forKey: "widget_artwork_path")
        } else if song == nil {
            ud.removeObject(forKey: "widget_artwork_path")
        }

        reloadTimelinesThrottled()
    }

    /// Lightweight update: only writes the play/pause state and reloads timelines.
    /// Called when the user taps play/pause without changing tracks.
    func updatePlayState(isPlaying: Bool) {
        defaults?.set(isPlaying, forKey: "widget_is_playing")
        reloadTimelinesThrottled()
    }

    // MARK: - Private Helpers

    /// Calls `WidgetCenter.shared.reloadAllTimelines()` at most once every 2 seconds.
    private func reloadTimelinesThrottled() {
        guard Date().timeIntervalSince(lastReloadTime) >= 2.0 else { return }
        lastReloadTime = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
