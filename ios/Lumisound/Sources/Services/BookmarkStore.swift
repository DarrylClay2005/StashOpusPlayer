import Foundation

// MARK: - BookmarkStore
//
// Named timestamp markers within a track — useful for long mixes, podcasts,
// or audiobook-style files where jumping back to "the drop at 12:30" or
// "chapter 3" matters. Keyed by `Song.id` (stable across rescans, same
// reasoning as `PlayHistoryStore`), persisted locally via UserDefaults.
// Entirely on-device; no server involved.

struct TrackBookmark: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var timestamp: TimeInterval
    var label: String
    var createdAt: Date = Date()
}

@MainActor
final class BookmarkStore {
    static let shared = BookmarkStore()

    private let key = "trackBookmarks.v1"
    private(set) var bookmarksBySong: [String: [TrackBookmark]] = [:]

    private init() { load() }

    func bookmarks(for songID: String) -> [TrackBookmark] {
        (bookmarksBySong[songID] ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    @discardableResult
    func addBookmark(songID: String, timestamp: TimeInterval, label: String) -> TrackBookmark {
        let bookmark = TrackBookmark(timestamp: timestamp, label: label)
        bookmarksBySong[songID, default: []].append(bookmark)
        save()
        return bookmark
    }

    func removeBookmark(songID: String, bookmarkID: String) {
        bookmarksBySong[songID]?.removeAll { $0.id == bookmarkID }
        if bookmarksBySong[songID]?.isEmpty == true {
            bookmarksBySong.removeValue(forKey: songID)
        }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [TrackBookmark]].self, from: data) {
            bookmarksBySong = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarksBySong) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
