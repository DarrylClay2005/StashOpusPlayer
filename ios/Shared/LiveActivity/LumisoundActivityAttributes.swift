import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Shared between the `Lumisound` app target and the `LumisoundWidget` extension
/// target (both list this exact file in their `project.yml` sources) so the two
/// processes agree on the Live Activity's data shape without a framework.
///
/// Artwork is intentionally NOT part of `ContentState` — like the rest of the
/// widget stack it's read straight off the shared App Group container
/// (`widget_artwork.jpg`, written by `WidgetDataService`) at render time.
@available(iOS 16.1, *)
struct LumisoundActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var position: TimeInterval
        var duration: TimeInterval
        /// The moment `position`/`isPlaying` were captured — lets the Live
        /// Activity's `Text(timerInterval:)` keep ticking between updates.
        var anchorDate: Date
        /// Mirrors `LibraryManager.isFavorite(songID:)` for the current
        /// track — drives the heart button's filled/outline state. Reuses
        /// the Home Screen widget's existing `ToggleFavoriteIntent`.
        var isFavorite: Bool = false

        var trackRange: ClosedRange<Date> {
            let start = anchorDate.addingTimeInterval(-position)
            let end = start.addingTimeInterval(max(duration, position))
            return start...max(start, end)
        }
    }
}
