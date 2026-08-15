import ActivityKit
import Foundation
import UIKit

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

    /// `Activity.request()` requires the app to be in the FOREGROUND to
    /// start a new activity — a call while backgrounded (the normal state
    /// during background audio playback) throws "Target is not foreground"
    /// every single time, and since that failure leaves `activity` nil,
    /// EVERY subsequent track change re-attempted the request — which,
    /// while a request from the foreground app WAS occasionally in flight
    /// (e.g. the user glancing at Now Playing between background stretches),
    /// meant a fresh system "Allow Live Activities?" consent prompt queued
    /// up per attempt, stacking on top of whichever one the user hadn't
    /// gotten to yet. This was the "shows every time I play a new song,
    /// multiple prompts stacked" report. Skip the request outright when not
    /// foreground (an update-only call still reaches the running activity
    /// fine once one exists — no functional loss, this only affects
    /// STARTING a brand new one), and back off for a while after any
    /// failure so a genuine one-off error doesn't retry on literally the
    /// very next track too.
    private static var lastRequestFailureAt: Date?
    private static let requestRetryCooldown: TimeInterval = 60

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

        // Starting (not updating) an Activity requires the foreground —
        // see the doc comment above. Silently skip rather than logging;
        // this is routine during background playback, not an error.
        guard UIApplication.shared.applicationState == .active else { return }

        if let lastFailure = lastRequestFailureAt, Date().timeIntervalSince(lastFailure) < requestRetryCooldown {
            return
        }

        do {
            activity = try Activity<LumisoundActivityAttributes>.request(
                attributes: LumisoundActivityAttributes(),
                contentState: state,
                pushType: nil
            )
            lastRequestFailureAt = nil
        } catch {
            lastRequestFailureAt = Date()
            appError("LiveActivityManager: failed to start activity: \(error.localizedDescription)", category: "widget")
        }
    }
}
