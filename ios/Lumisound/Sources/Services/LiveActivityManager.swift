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
    /// Mirrors `WidgetDataService`'s `widget_is_favorite` for the Home Screen
    /// widget — kept here too so `updateFavoriteState` can push a heart-icon
    /// change to the Live Activity without needing isPlaying/position/
    /// duration re-supplied (see that function).
    private static var lastIsFavorite = false
    private static var lastIsPlaying = false
    private static var lastPosition: TimeInterval = 0
    private static var lastDuration: TimeInterval = 0

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
    static func update(song: Song?, isPlaying: Bool, position: TimeInterval, duration: TimeInterval, isFavorite: Bool) {
        guard let song else {
            end()
            return
        }
        lastTitle = song.displayName
        lastArtist = song.artistName
        lastIsFavorite = isFavorite
        pushState(isPlaying: isPlaying, position: position, duration: duration)
    }

    /// Lightweight update: play/pause or position changes on the already-current
    /// track. No-op if no Activity is running (nothing to update).
    static func updatePlayState(isPlaying: Bool, position: TimeInterval, duration: TimeInterval) {
        guard activity != nil else { return }
        pushState(isPlaying: isPlaying, position: position, duration: duration)
    }

    /// Lightweight update: the current track's favorite flag changed (toggled
    /// from in-app UI, the Home Screen widget, or this Live Activity's own
    /// heart button — see `ToggleFavoriteIntent`). No-op if no Activity is
    /// running. Reuses the last-known play state/position/duration since
    /// only the favorite flag actually changed.
    static func updateFavoriteState(isFavorite: Bool) {
        lastIsFavorite = isFavorite
        guard activity != nil else { return }
        pushState(isPlaying: lastIsPlaying, position: lastPosition, duration: lastDuration)
    }

    static func end() {
        guard let activity else { return }
        let finalState = LumisoundActivityAttributes.ContentState(
            title: lastTitle, artist: lastArtist, isPlaying: false,
            position: 0, duration: 0, anchorDate: Date(), isFavorite: lastIsFavorite
        )
        Task {
            await activity.end(using: finalState, dismissalPolicy: .immediate)
        }
        self.activity = nil
    }

    private static func pushState(isPlaying: Bool, position: TimeInterval, duration: TimeInterval) {
        lastIsPlaying = isPlaying
        lastPosition = position
        lastDuration = duration
        let state = LumisoundActivityAttributes.ContentState(
            title: lastTitle, artist: lastArtist, isPlaying: isPlaying,
            position: position, duration: duration, anchorDate: Date(), isFavorite: lastIsFavorite
        )

        if let activity {
            Task { await activity.update(using: state) }
            return
        }

        // A Live Activity outlives this process (up to iOS's own ~8h budget) —
        // `self.activity` only resets to nil because it's an in-memory static,
        // not because the activity itself ended. Every app relaunch after a
        // background kill (routine for a backgrounded audio app — this is NOT
        // a crash) landed here with a real activity still alive on iOS's side
        // but no in-process reference to it, so the next track change called
        // `.request()` again — a SECOND concurrent activity of the same type,
        // which is exactly the shape of thing that stacks duplicate "Allow
        // Live Activities?" prompts (each independent `.request()` call is a
        // fresh ask as far as the system's concerned, regardless of a prior
        // one already being granted). Re-attach to it instead — `Activity
        // .activities` is OS-tracked and survives process relaunch, unlike
        // this enum's own static state.
        if let existing = Activity<LumisoundActivityAttributes>.activities.first {
            activity = existing
            Task { await existing.update(using: state) }
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
            // "Maximum number of activities for target already exists" —
            // `self.activity` resets to nil on every fresh process launch,
            // including a crash (no graceful shutdown path ever runs
            // `end()`), so a Live Activity from a PRIOR crashed session
            // stays alive on iOS's side indefinitely — this process just
            // has no reference to it. Enough crashes across a session and
            // these orphans pile up until iOS's own per-app cap is hit,
            // which is exactly this error. End every activity this type
            // has (not just the one this process happens to remember) so
            // the NEXT attempt has room, instead of staying permanently
            // stuck failing every future request until the user force-
            // quits the app (the only thing that currently clears it).
            let orphans = Activity<LumisoundActivityAttributes>.activities
            guard !orphans.isEmpty else { return }
            appWarn("LiveActivityManager: ending \(orphans.count) orphaned activity(s) from prior session(s)", category: "widget")
            Task {
                for orphan in orphans {
                    // `.content` (to resubmit the orphan's own current state
                    // while ending it) needs iOS 16.2 — this enum's own
                    // minimum is 16.1, so that read isn't always available.
                    // Ending is what actually matters here (freeing the slot
                    // for a NEW request); a nil-state end on older OSes just
                    // means the dismissed activity's last frame doesn't get
                    // touched up first, which nobody sees since it's already
                    // being dismissed immediately.
                    if #available(iOS 16.2, *) {
                        await orphan.end(using: orphan.content.state, dismissalPolicy: .immediate)
                    } else {
                        await orphan.end(using: nil, dismissalPolicy: .immediate)
                    }
                }
            }
        }
    }
}
