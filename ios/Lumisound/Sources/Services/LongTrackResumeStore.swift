import Foundation

/// Automatically remembers playback position for long local tracks (DJ
/// mixes, audiobooks, anything over `minimumDuration`) — the same silent
/// "continue where you left off" treatment podcasts already get via their
/// own per-episode progress tracking, extended to regular library tracks.
/// Distinct from `BookmarkStore`: bookmarks are user-created, named, and
/// multiple per track; this is one silent, auto-updating position per
/// long track with nothing for the user to create or manage — see
/// `LongTrackResumeService`, which actually drives it during playback.
struct LongTrackResumePoint: Codable {
    var position: TimeInterval
    var updatedAt: Date
}

@MainActor
final class LongTrackResumeStore {
    static let shared = LongTrackResumeStore()

    /// Tracks shorter than this never get a resume point — a 4-minute pop
    /// song doesn't need one.
    static let minimumDuration: TimeInterval = 20 * 60
    /// A saved position within this many seconds of the track's end is
    /// treated as "finished", not "partway through" — resuming at
    /// 0:03 left would just be noise.
    static let nearEndMargin: TimeInterval = 30

    private let key = "longTrackResumePoints.v1"
    private var entries: [String: LongTrackResumePoint]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: LongTrackResumePoint].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    /// Returns a saved position worth resuming from, or `nil` if the track
    /// is too short, has no saved position, the position is too close to
    /// the very start, or too close to the end to be meaningful.
    func resumePosition(for song: Song) -> TimeInterval? {
        guard song.duration >= Self.minimumDuration, let entry = entries[song.id] else { return nil }
        guard entry.position > 5, entry.position < song.duration - Self.nearEndMargin else { return nil }
        return entry.position
    }

    func recordPosition(_ position: TimeInterval, for song: Song) {
        guard song.duration >= Self.minimumDuration else { return }
        entries[song.id] = LongTrackResumePoint(position: position, updatedAt: Date())
        save()
    }

    func clear(for songID: Song.ID) {
        guard entries[songID] != nil else { return }
        entries[songID] = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
