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

    /// Tolerance (in seconds) used when comparing two songs' `duration` for the
    /// "same title & artist" secondary match. Re-encodes/re-downloads of the same
    /// source track can differ by a fraction of a second due to container overhead
    /// or trimming, so an exact match is too strict.
    static let durationTolerance: TimeInterval = 2.0

    /// Groups `songs` into sets of likely duplicates. Two songs are considered
    /// duplicates if either:
    ///  - they share the same non-empty `sourceTrackID` (e.g. both were
    ///    downloaded from the same YouTube/SoundCloud track via the stream
    ///    search, tagged with the `LUMISOUND_ID` metadata tag) — this is the
    ///    "definite duplicate" case, regardless of duration, or
    ///  - they have the same normalized title + artist (case/whitespace/
    ///    punctuation-insensitive) AND their durations are within
    ///    `durationTolerance` of each other — this catches duplicates imported
    ///    from different sources (e.g. once via Apple Music, once via download,
    ///    or two separate re-downloads of the same track under different
    ///    filenames/IDs). Title+artist matches whose durations differ by more
    ///    than the tolerance are treated as distinct tracks (e.g. a "Radio Edit"
    ///    vs an "Extended Mix" sharing a title) and are not grouped together.
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

    /// Songs that "Delete All Duplicates" would remove: for each group, the
    /// longest removable (downloaded, not Apple Music) copy is kept and every
    /// other removable copy is queued for deletion. Apple Music copies are
    /// never included since they can't be removed from here.
    var allDuplicatesToRemove: [Song] {
        duplicateGroups.flatMap { group -> [Song] in
            let removable = group.songs.filter { $0.persistentID == nil && $0.url != nil }
            guard removable.count > 1 else { return [] }
            let sorted = removable.sorted { a, b in
                if abs(a.duration - b.duration) > 0.01 {
                    return a.duration > b.duration
                }
                // Tiebreaker for same-duration copies: prefer to keep the one
                // with a known BPM. A successful BPM analysis means the file
                // decoded cleanly end-to-end, while a copy that previously
                // failed analysis (nil bpm) may be truncated or corrupt.
                let aHasBPM = a.bpm != nil
                let bHasBPM = b.bpm != nil
                return aHasBPM && !bHasBPM
            }
            return Array(sorted.dropFirst())
        }
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

        // Second pass: group remaining songs by normalized title + artist, then
        // split each of those groups further by duration — only songs whose
        // durations fall within `durationTolerance` of each other are considered
        // the same track (re-downloads/re-encodes vs. genuinely different
        // versions sharing a title, e.g. "Radio Edit" vs "Extended Mix").
        var byTitleArtist: [String: [Song]] = [:]
        for song in songs where !consumed.contains(song.id) {
            let key = normalize(song.title) + "|" + normalize(song.artist)
            guard !key.isEmpty, key != "|" else { continue }
            byTitleArtist[key, default: []].append(song)
        }
        for (_, candidates) in byTitleArtist where candidates.count > 1 {
            for cluster in clusterByDuration(candidates) where cluster.count > 1 {
                groups.append(DuplicateGroup(id: UUID(), songs: cluster, reason: .sameTitleAndArtist))
            }
        }

        return groups.sorted { $0.songs.count > $1.songs.count }
    }

    /// Splits `songs` (already grouped by normalized title + artist) into clusters
    /// where every pair of durations within a cluster is within
    /// `durationTolerance` of each other. Sorts by duration first and then does a
    /// simple chain-grouping pass, so e.g. durations [120, 121, 122, 200, 201]
    /// with a 2s tolerance become two clusters: [120, 121, 122] and [200, 201].
    nonisolated private static func clusterByDuration(_ songs: [Song]) -> [[Song]] {
        let sorted = songs.sorted { $0.duration < $1.duration }
        var clusters: [[Song]] = []
        var current: [Song] = []
        var clusterStart: TimeInterval?

        for song in sorted {
            if let start = clusterStart, song.duration - start > durationTolerance {
                clusters.append(current)
                current = []
                clusterStart = nil
            }
            if clusterStart == nil { clusterStart = song.duration }
            current.append(song)
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    /// Lowercases, strips diacritics/punctuation, and collapses whitespace so
    /// e.g. "Daft Punk - One More Time (Radio Edit)" and "daft punk one more
    /// time radio edit" match.
    nonisolated static func normalize(_ text: String) -> String {
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

    /// Combined playtime of every copy in this group, e.g. "8:42 total" across
    /// 3 copies — shown alongside each copy's own duration so the user can
    /// judge which copy is more complete (longer = likely fewer cuts/ads).
    var totalDuration: TimeInterval {
        songs.reduce(0) { $0 + $1.duration }
    }
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
