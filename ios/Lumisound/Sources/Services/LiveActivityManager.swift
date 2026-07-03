import ActivityKit
import Foundation

/// Starts/updates/ends the Lock Screen + Dynamic Island Live Activity for the
/// current track. Purely local (no push updates — `pushType: nil`), driven by
/// the same call sites that already feed `WidgetDataService`, so playback state
/// only has to be computed once per change.
@available(iOS 16.1, *)
@MainActor
enum LiveActivityManager {
    private static var activity: Activity<LumisoundActivityAttributes>?
    private static var lastTitle = ""
    private static var lastArtist = ""

    /// Full update: called when the current song changes (or clears). Starts a
    /// new Activity if none is running yet, otherwise just refreshes its state.
    static func update(song: Song?, isPlaying: Bool, position: TimeInterval, duration: TimeInterval) {
        guard let song else {
            end()
            return
        }
        lastTitle = song.displayName
        lastArtist = song.artistName
        pushState(isPlaying: isPlaying, position: position, duration: duration)
    }

    /// Lightweight update: play/pause or position changes on the already-current
    /// track. No-op if no Activity is running (nothing to update).
    static func updatePlayState(isPlaying: Bool, position: TimeInterval, duration: TimeInterval) {
        guard activity != nil else { return }
        pushState(isPlaying: isPlaying, position: position, duration: duration)
    }

    static func end() {
        guard let activity else { return }
        let finalState = LumisoundActivityAttributes.ContentState(
            title: lastTitle, artist: lastArtist, isPlaying: false,
            position: 0, duration: 0, anchorDate: Date()
        )
        Task {
            await activity.end(using: finalState, dismissalPolicy: .immediate)
        }
        self.activity = nil
    }

    private static func pushState(isPlaying: Bool, position: TimeInterval, duration: TimeInterval) {
        let state = LumisoundActivityAttributes.ContentState(
            title: lastTitle, artist: lastArtist, isPlaying: isPlaying,
            position: position, duration: duration, anchorDate: Date()
        )

        if let activity {
            Task { await activity.update(using: state) }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity<LumisoundActivityAttributes>.request(
                attributes: LumisoundActivityAttributes(),
                contentState: state,
                pushType: nil
            )
        } catch {
            appError("LiveActivityManager: failed to start activity: \(error.localizedDescription)", category: "widget")
        }
    }
}
