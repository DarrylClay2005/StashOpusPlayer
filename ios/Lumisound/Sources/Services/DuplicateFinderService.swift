import Foundation

// MARK: - DuplicateFinderService

@MainActor
final class DuplicateFinderService: ObservableObject {

    // MARK: Singleton

    static let shared = DuplicateFinderService()
    private init() {}

    // MARK: Published State

    @Published private(set) var isScanning = false
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var lastScanDate: Date? = {
        let ts = UserDefaults.standard.double(forKey: "duplicateFinder_lastScanTimestamp")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }()

    // MARK: - Scan

    /// Groups `songs` into sets of likely duplicates. Two songs are considered
    /// duplicates if either:
    ///  - they share the same non-empty `sourceTrackID` (e.g. both were
    ///    downloaded from the same YouTube/SoundCloud track via the stream
    ///    search, tagged with the `LUMISOUND_ID` metadata tag), or
    ///  - they have the same normalized title + artist (case/whitespace/
    ///    punctuation-insensitive), which catches duplicates imported from
    ///    different sources (e.g. once via Apple Music, once via download).
    func runScan(songs: [Song]) async {
        guard !isScanning else { return }
        isScanning = true

        let groups = await Task.detached(priority: .utility) {
            DuplicateFinderService.findDuplicates(in: songs)
        }.value

        duplicateGroups = groups
        let now = Date()
        lastScanDate = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "duplicateFinder_lastScanTimestamp")
        isScanning = false
    }

    /// Removes a single song from `duplicateGroups` (e.g. after it's been
    /// deleted from the library), dropping any group that's left with fewer
    /// than two songs.
    func removeSongFromGroups(songID: String) {
        duplicateGroups = duplicateGroups.compactMap { group in
            var songs = group.songs
            songs.removeAll { $0.id == songID }
            guard songs.count > 1 else { return nil }
            return DuplicateGroup(id: group.id, songs: songs, reason: group.reason)
        }
    }

    // MARK: - Private Worker (nonisolated, runs off main actor)

    nonisolated private static func findDuplicates(in songs: [Song]) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        var consumed = Set<String>()

        // First pass: group by shared source track ID (most reliable signal —
        // same exact upstream track downloaded more than once).
        var bySourceID: [String: [Song]] = [:]
        for song in songs {
            guard let sourceID = song.sourceTrackID, !sourceID.isEmpty else { continue }
            bySourceID[sourceID, default: []].append(song)
        }
        for (_, group) in bySourceID where group.count > 1 {
            groups.append(DuplicateGroup(id: UUID(), songs: group, reason: .sameSourceTrack))
            consumed.formUnion(group.map(\.id))
        }

        // Second pass: group remaining songs by normalized title + artist.
        var byTitleArtist: [String: [Song]] = [:]
        for song in songs where !consumed.contains(song.id) {
            let key = normalize(song.title) + "|" + normalize(song.artist)
            guard !key.isEmpty, key != "|" else { continue }
            byTitleArtist[key, default: []].append(song)
        }
        for (_, group) in byTitleArtist where group.count > 1 {
            groups.append(DuplicateGroup(id: UUID(), songs: group, reason: .sameTitleAndArtist))
        }

        return groups.sorted { $0.songs.count > $1.songs.count }
    }

    /// Lowercases, strips diacritics/punctuation, and collapses whitespace so
    /// e.g. "Daft Punk - One More Time (Radio Edit)" and "daft punk one more
    /// time radio edit" match.
    nonisolated private static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let alphanumeric = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(alphanumeric))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - DuplicateGroup

struct DuplicateGroup: Identifiable {
    let id: UUID
    let songs: [Song]
    let reason: DuplicateReason
}

// MARK: - DuplicateReason

enum DuplicateReason {
    case sameSourceTrack
    case sameTitleAndArtist

    var label: String {
        switch self {
        case .sameSourceTrack: return "Same source track"
        case .sameTitleAndArtist: return "Same title & artist"
        }
    }
}
