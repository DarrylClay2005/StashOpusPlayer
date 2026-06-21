import Foundation
import Combine

// MARK: - Smart Playlist model
//
// A dynamic, rules-based playlist. Unlike a normal playlist (a fixed list of
// song IDs), a smart playlist stores a set of rules that are evaluated live
// against `LibraryManager.allSongs` every time it's opened — so "Favorites
// added recently", "120-135 BPM workout", "downloaded from YouTube", etc. stay
// up to date on their own. Stored locally (UserDefaults); no server dependency.

enum SmartField: String, Codable, CaseIterable, Identifiable {
    case title, artist, album, genre, year, duration, bpm, favorite, source

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .genre: return "Genre"
        case .year: return "Year"
        case .duration: return "Duration (sec)"
        case .bpm: return "BPM"
        case .favorite: return "Favorite"
        case .source: return "Source"
        }
    }

    var kind: SmartFieldKind {
        switch self {
        case .title, .artist, .album, .genre: return .text
        case .year, .duration, .bpm: return .number
        case .favorite: return .boolean
        case .source: return .source
        }
    }
}

enum SmartFieldKind { case text, number, boolean, source }

enum SmartOp: String, Codable, CaseIterable, Identifiable {
    case contains, notContains, equals, greaterThan, lessThan, between, isTrue, isFalse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .equals: return "is"
        case .greaterThan: return "greater than"
        case .lessThan: return "less than"
        case .between: return "between"
        case .isTrue: return "is yes"
        case .isFalse: return "is no"
        }
    }

    /// The operators that make sense for a given field kind.
    static func available(for kind: SmartFieldKind) -> [SmartOp] {
        switch kind {
        case .text:    return [.contains, .notContains, .equals]
        case .number:  return [.equals, .greaterThan, .lessThan, .between]
        case .boolean: return [.isTrue, .isFalse]
        case .source:  return [.equals]
        }
    }
}

/// Possible values for the `.source` field.
enum SmartSource: String, Codable, CaseIterable, Identifiable {
    case youtube, soundcloud, local
    var id: String { rawValue }
    var label: String {
        switch self {
        case .youtube: return "YouTube"
        case .soundcloud: return "SoundCloud"
        case .local: return "On-device / Imported"
        }
    }
}

struct SmartRule: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var field: SmartField = .title
    var op: SmartOp = .contains
    var text: String = ""
    var number: Double = 0
    var number2: Double = 0   // upper bound for `.between`
    var source: SmartSource = .youtube
}

enum SmartMatch: String, Codable, CaseIterable, Identifiable {
    case all, any
    var id: String { rawValue }
    var label: String { self == .all ? "Match ALL rules" : "Match ANY rule" }
}

enum SmartSort: String, Codable, CaseIterable, Identifiable {
    case titleAsc, artistAsc, yearDesc, bpmAsc, durationAsc, random
    var id: String { rawValue }
    var label: String {
        switch self {
        case .titleAsc: return "Title (A–Z)"
        case .artistAsc: return "Artist (A–Z)"
        case .yearDesc: return "Year (newest)"
        case .bpmAsc: return "BPM (low→high)"
        case .durationAsc: return "Duration (short→long)"
        case .random: return "Random"
        }
    }
}

struct SmartPlaylist: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String = "New Smart Playlist"
    var icon: String = "sparkles"
    var match: SmartMatch = .all
    var rules: [SmartRule] = []
    var limit: Int = 0        // 0 = unlimited
    var sort: SmartSort = .titleAsc

    // MARK: Evaluation

    /// Returns the songs from `songs` that satisfy this playlist's rules, sorted
    /// and limited. `favorites` is `LibraryManager.favoriteSongIDs`.
    func evaluate(over songs: [Song], favorites: Set<String>) -> [Song] {
        let filtered = songs.filter { matches($0, favorites: favorites) }
        let sorted = sortSongs(filtered)
        if limit > 0 { return Array(sorted.prefix(limit)) }
        return sorted
    }

    func matches(_ song: Song, favorites: Set<String>) -> Bool {
        guard !rules.isEmpty else { return true }
        let results = rules.map { evaluate(rule: $0, song: song, favorites: favorites) }
        return match == .all ? results.allSatisfy { $0 } : results.contains(true)
    }

    private func evaluate(rule: SmartRule, song: Song, favorites: Set<String>) -> Bool {
        switch rule.field.kind {
        case .text:
            let value = textValue(of: rule.field, in: song)
            switch rule.op {
            case .contains:    return value.localizedCaseInsensitiveContains(rule.text)
            case .notContains: return !value.localizedCaseInsensitiveContains(rule.text)
            case .equals:      return value.compare(rule.text, options: .caseInsensitive) == .orderedSame
            default:           return false
            }
        case .number:
            guard let value = numberValue(of: rule.field, in: song) else { return false }
            switch rule.op {
            case .equals:      return abs(value - rule.number) < 0.5
            case .greaterThan: return value > rule.number
            case .lessThan:    return value < rule.number
            case .between:
                let lo = min(rule.number, rule.number2)
                let hi = max(rule.number, rule.number2)
                return value >= lo && value <= hi
            default:           return false
            }
        case .boolean:
            let isFav = favorites.contains(song.id)
            return rule.op == .isTrue ? isFav : !isFav
        case .source:
            return sourceValue(of: song) == rule.source
        }
    }

    private func textValue(of field: SmartField, in song: Song) -> String {
        switch field {
        case .title:  return song.title
        case .artist: return song.artist
        case .album:  return song.album
        case .genre:  return song.genre
        default:      return ""
        }
    }

    private func numberValue(of field: SmartField, in song: Song) -> Double? {
        switch field {
        case .year:     return Double(song.year.trimmingCharacters(in: .whitespaces))
        case .duration: return song.duration > 0 ? song.duration : nil
        case .bpm:      return song.bpm
        default:        return nil
        }
    }

    private func sourceValue(of song: Song) -> SmartSource {
        guard let s = song.sourceTrackID?.lowercased() else { return .local }
        if s.hasPrefix("youtube") { return .youtube }
        if s.hasPrefix("soundcloud") { return .soundcloud }
        return .local
    }

    private func sortSongs(_ songs: [Song]) -> [Song] {
        switch sort {
        case .titleAsc:    return songs.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .artistAsc:   return songs.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .yearDesc:    return songs.sorted { (Int($0.year) ?? 0) > (Int($1.year) ?? 0) }
        case .bpmAsc:      return songs.sorted { ($0.bpm ?? 0) < ($1.bpm ?? 0) }
        case .durationAsc: return songs.sorted { $0.duration < $1.duration }
        case .random:      return songs.shuffled()
        }
    }
}

// MARK: - SmartPlaylistStore

/// Local persistence for smart playlists (UserDefaults-backed), mirroring
/// `TrackedPlaylistStore`. No server sync — smart playlists are derived data.
@MainActor
final class SmartPlaylistStore: ObservableObject {
    static let shared = SmartPlaylistStore()

    @Published private(set) var playlists: [SmartPlaylist] = []

    private let key = "smartPlaylists.v1"

    init() { load() }

    func add(_ playlist: SmartPlaylist) {
        playlists.append(playlist)
        save()
    }

    func update(_ playlist: SmartPlaylist) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlist.id }) else {
            add(playlist); return
        }
        playlists[idx] = playlist
        save()
    }

    func remove(id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([SmartPlaylist].self, from: data) {
            playlists = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
