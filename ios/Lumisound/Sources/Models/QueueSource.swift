import Foundation

/// How a track ended up in the playback queue.
///
/// This is the real distinction the Queue rework depends on — not just a
/// visual label slapped on the UI. `AudioPlayerManager+Queue`'s
/// `insertNext(song:source:)` and `appendToQueue(song:source:)` are the ONLY
/// two entry points every "Play Next" / "Add to Queue" action in the app
/// funnels through (menus, streaming search results, Discover Mix, On This
/// Day, etc.), and they default to tagging what they insert as `.manual`.
/// Everything else reads as `.autoContinuation`: the base playlist/album/
/// library list loaded via `setQueue`, and Auto-Radio's own continuation
/// tracks (`LumisoundApp`'s auto-radio `.onReceive` explicitly passes
/// `.autoContinuation` when it appends a related track it found on its own).
///
/// Stored per-instance on `Song` (see `Song.queueSource`) rather than tracked
/// by queue index — a `Song` is a value type, so its tag travels with it
/// automatically through drag-reorders, shuffles, and cross-device sync
/// round-trips, without needing separate index bookkeeping that would drift
/// out of sync every time the queue is mutated by code outside this file.
enum QueueSource: String, Codable, Hashable, Sendable {
    /// Explicitly queued by the user. Rendered in its own "Manually Queued"
    /// section immediately after the current track — ahead of wherever the
    /// auto-continuation would otherwise pick up — and never silently
    /// reordered, deduplicated, or dropped by shuffle/repeat logic.
    case manual
    /// Part of the natural playback context: the playlist/album/library list
    /// currently loaded, or a track Auto-Radio appended to keep playback
    /// going once the loaded context runs out.
    case autoContinuation = "auto_continuation"
}
