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

    // MARK: - Cloud library check (acoustic fingerprint, server-side)
    //
    // Separate from the on-device scan above: this calls the bridge's
    // /user/library/acoustic-duplicates, which fingerprints (fpcalc/Chromaprint)
    // every file in the user's CLOUD-backed library and groups ones that are
    // acoustically the same recording — catches copies the title/artist match
    // above misses (differently-tagged re-encodes, etc.). Deliberately NOT
    // merged into `duplicateGroups`: correlating a cloud filename back to a
    // specific local `Song` isn't reliable (backup filenames aren't guaranteed
    // to match 1:1), so results are shown as their own informational list —
    // scoped to what the server actually told us, no risk of mis-attributing
    // a match to the wrong local file.

    @Published private(set) var isCheckingCloud = false
    @Published private(set) var cloudDuplicateGroups: [[CloudDuplicateFile]] = []
    @Published private(set) var cloudCheckError: String?

    struct CloudDuplicateFile: Identifiable {
        let id = UUID()
        let filename: String
        let duration: TimeInterval
    }

    func checkCloudDuplicates() async {
        guard !isCheckingCloud else { return }
        guard let account = AccountService.shared, account.isLoggedIn, let token = account.token else {
            cloudCheckError = "Sign in to check your cloud library."
            return
        }
        isCheckingCloud = true
        cloudCheckError = nil
        defer { isCheckingCloud = false }

        let base = account.bridgeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/user/library/acoustic-duplicates") else {
            cloudCheckError = "Invalid bridge URL"
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // fpcalc-scanning up to 300 cloud files can genuinely take a while —
        // well past the ~20s timeout used for quick lookups elsewhere.
        request.timeoutInterval = 90

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                cloudCheckError = "Server error (HTTP \(http.statusCode))"
                return
            }
            let decoded = try JSONDecoder().decode(AcousticDuplicatesResponse.self, from: data)
            cloudDuplicateGroups = decoded.duplicateGroups.map { group in
                group.map { CloudDuplicateFile(filename: $0.file, duration: $0.duration) }
            }
        } catch {
            cloudCheckError = error.localizedDescription
        }
    }

    private struct AcousticDuplicatesResponse: Decodable {
        let duplicateGroups: [[AcousticDuplicateEntry]]

        enum CodingKeys: String, CodingKey {
            case duplicateGroups = "duplicate_groups"
        }
    }

    private struct AcousticDuplicateEntry: Decodable {
        let file: String
        let duration: Double
    }

    // MARK: - Scan

    /// Tolerance (in seconds) used when comparing two songs' `duration` for the
    /// "same title & artist" secondary match. Re-encodes/re-downloads of the same
    /// source track can differ by a fraction of a second due to container overhead
    /// or trimming, so an exact match is too strict.
    static let durationTolerance: TimeInterval = 2.0

    /// Groups `songs` into sets of likely duplicates, in three passes (see
    /// `findDuplicates`):
    ///  1. Same non-empty `sourceTrackID` (e.g. both downloaded from the same
    ///     YouTube/SoundCloud track, tagged with the `LUMISOUND_ID` metadata
    ///     tag) — the "definite duplicate" case, regardless of duration.
    ///  2. For everything else, candidates are first narrowed by duration
    ///     (`durationTolerance`), then CONFIRMED by actually comparing how
    ///     the audio sounds — `AudioFingerprintService.matchThreshold`
    ///     cosine similarity on a coarse spectral profile — for any song
    ///     whose file is locally readable. This is what catches duplicates
    ///     re-titled or re-tagged differently across sources, which text
    ///     matching alone can't.
    ///  3. Songs a duration cluster couldn't fingerprint (Apple Music items,
    ///     unreadable files) or that didn't acoustically match anything fall
    ///     back to the old normalized title + artist check within that same
    ///     duration cluster.
    func runScan(songs: [Song]) async {
        guard !isScanning else { return }
        isScanning = true
        appLog("DuplicateFinderService: scan started (\(songs.count) songs)", category: "audio")

        let groups = await DuplicateFinderService.findDuplicates(in: songs)

        appLog(
            "DuplicateFinderService: scan finished — \(groups.count) group(s), reasons: "
                + Dictionary(grouping: groups, by: { $0.reason.label })
                    .map { "\($0.key)×\($0.value.count)" }.sorted().joined(separator: ", "),
            category: "audio"
        )
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

    /// Hard cap on total fingerprints computed per scan — bounds worst-case
    /// scan time on a large library where many unrelated songs happen to
    /// share a close duration (a weak signal on its own; see the clustering
    /// step below). Cache hits (repeat scans) don't count against this.
    private static let maxFingerprintsPerScan = 150

    /// Duration clusters larger than this skip acoustic comparison entirely
    /// and fall straight back to the title+artist check — a cluster this
    /// size means duration alone isn't narrowing things down at all (e.g. a
    /// library with many similarly-timed tracks), so fingerprinting every
    /// pair would spend most of the budget on near-certain non-matches.
    private static let maxClusterSizeForAcoustic = 20

    nonisolated private static func findDuplicates(in songs: [Song]) async -> [DuplicateGroup] {
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
        appLog("DuplicateFinderService: pass 1 (source track ID) — \(consumed.count) song(s) grouped", category: "audio")

        // Second pass: cluster whatever's left by duration alone (not
        // gated on title matching first, unlike before) — within each
        // cluster, prefer ACTUALLY LISTENING to confirm a match over
        // trusting text: songs with a locally-readable file are compared
        // acoustically via AudioFingerprintService (the offline counterpart
        // to the live Auto EQ/Smart Crossfade analyzer — see its doc
        // comment), and only songs that can't be fingerprinted (Apple Music
        // items, unreadable files) or that don't acoustically match anything
        // fall back to the old normalized-title+artist check.
        let remaining = songs.filter { !consumed.contains($0.id) }
        let clusters = clusterByDuration(remaining)
        var fingerprintsComputed = 0
        var acousticGroupCount = 0
        var fallbackGroupCount = 0

        for cluster in clusters where cluster.count > 1 {
            var clusterConsumed = Set<String>()

            let fingerprintable = cluster.filter { song in
                guard let url = song.url else { return false }
                return FileManager.default.fileExists(atPath: url.path)
            }
            if fingerprintable.count > 1 && fingerprintable.count <= maxClusterSizeForAcoustic {
                var vectors: [String: [Float]] = [:]
                for song in fingerprintable {
                    guard let url = song.url else { continue }
                    if fingerprintsComputed >= maxFingerprintsPerScan {
                        appWarn("DuplicateFinderService: fingerprint budget (\(maxFingerprintsPerScan)) exhausted this scan — remaining candidates fall back to title matching", category: "audio")
                        break
                    }
                    if let vector = await AudioFingerprintService.shared.fingerprint(for: url) {
                        vectors[song.id] = vector
                        fingerprintsComputed += 1
                    }
                }

                // Union-find: group songs whose pairwise cosine similarity
                // clears the match threshold, so A-matches-B-matches-C all
                // land in one group even if A-vs-C alone were borderline.
                var parent: [String: String] = [:]
                func find(_ x: String) -> String {
                    var x = x
                    while let p = parent[x], p != x { x = p }
                    return x
                }
                func union(_ a: String, _ b: String) {
                    let ra = find(a), rb = find(b)
                    if ra != rb { parent[ra] = rb }
                }
                for id in vectors.keys { parent[id] = id }
                let ids = Array(vectors.keys)
                for i in 0..<ids.count {
                    for j in (i + 1)..<ids.count {
                        guard let va = vectors[ids[i]], let vb = vectors[ids[j]] else { continue }
                        let similarity = AudioFingerprintService.cosineSimilarity(va, vb)
                        if similarity >= AudioFingerprintService.matchThreshold {
                            union(ids[i], ids[j])
                        }
                        appLog(
                            "DuplicateFinderService: acoustic similarity \(String(format: "%.4f", similarity)) between \"\(cluster.first(where: { $0.id == ids[i] })?.title ?? ids[i])\" and \"\(cluster.first(where: { $0.id == ids[j] })?.title ?? ids[j])\"",
                            category: "audio"
                        )
                    }
                }
                var byRoot: [String: [Song]] = [:]
                for song in fingerprintable where vectors[song.id] != nil {
                    byRoot[find(song.id), default: []].append(song)
                }
                for (_, matched) in byRoot where matched.count > 1 {
                    groups.append(DuplicateGroup(id: UUID(), songs: matched, reason: .acousticMatch))
                    clusterConsumed.formUnion(matched.map(\.id))
                    acousticGroupCount += 1
                }
            }

            // Fallback for whatever the acoustic pass didn't account for
            // (non-fingerprintable songs, songs whose fingerprint didn't
            // match anything, or an oversized cluster that skipped
            // fingerprinting entirely) — same normalized title+artist
            // check as before, scoped to this duration cluster.
            let leftover = cluster.filter { !clusterConsumed.contains($0.id) }
            var byTitleArtist: [String: [Song]] = [:]
            for song in leftover {
                let key = normalize(song.title) + "|" + normalizeArtist(song.artist)
                guard !key.isEmpty, key != "|" else { continue }
                byTitleArtist[key, default: []].append(song)
            }
            for (_, matched) in byTitleArtist where matched.count > 1 {
                groups.append(DuplicateGroup(id: UUID(), songs: matched, reason: .sameTitleAndArtist))
                fallbackGroupCount += 1
            }
        }
        appLog(
            "DuplicateFinderService: pass 2 — \(fingerprintsComputed) fingerprint(s) computed, "
                + "\(acousticGroupCount) acoustic group(s), \(fallbackGroupCount) title-fallback group(s)",
            category: "audio"
        )

        return groups.sorted { $0.songs.count > $1.songs.count }
    }

    /// Splits `songs` into clusters where every pair of durations within a
    /// cluster is within `durationTolerance` of each other — the candidate
    /// pool for pass 2's acoustic/title-fallback check above (duration alone
    /// is a weak signal, which is exactly why that pass confirms a real
    /// match acoustically rather than trusting a duration cluster on its
    /// own). Sorts by duration first and then does a simple chain-grouping
    /// pass, so e.g. durations [120, 121, 122, 200, 201] with a 2s tolerance
    /// become two clusters: [120, 121, 122] and [200, 201].
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

    /// Bracketed/parenthetical terms YouTube/SoundCloud uploaders routinely tack
    /// onto a title that do NOT represent a genuinely different recording —
    /// stripped before comparison so e.g. "Song Name" and "Song Name (Official
    /// Music Video)" match. Deliberately excludes real edition markers (Radio
    /// Edit, Extended Mix, Remix, Acoustic, Live, Instrumental, Cover, ...) so
    /// those stay distinct rather than being merged with the original.
    private static let titleNoiseTerms: Set<String> = [
        "official video", "official music video", "official audio",
        "official lyric video", "official lyrics video", "lyric video", "lyrics",
        "audio", "video", "hd", "hq", "4k", "music video", "visualizer", "mv",
        "full video", "with lyrics", "explicit", "clean", "clean version",
        "monstercat release", "audio only",
    ]

    /// Matches a `feat./ft./featuring <name>` clause, optionally wrapped in
    /// parens/brackets or introduced by a hyphen/comma — stripped from both
    /// titles and artists since the same track is tagged inconsistently
    /// with/without a feature credit across different uploads/sources.
    private static let featureClauseRegex = try? NSRegularExpression(
        pattern: #"(?i)[\(\[]?\s*(feat\.?|ft\.?|featuring)\s+[^()\[\],]+[\)\]]?"#
    )

    /// Lowercases, strips diacritics/punctuation, drops noise tags and feature
    /// credits, and collapses whitespace so e.g. "Daft Punk - One More Time
    /// (Official Audio)" and "daft punk one more time" match, while "(Radio
    /// Edit)" vs "(Extended Mix)" of the same title stay distinct.
    nonisolated static func normalize(_ text: String) -> String {
        var working = text
        if let featureClauseRegex {
            working = featureClauseRegex.stringByReplacingMatches(
                in: working, range: NSRange(working.startIndex..., in: working), withTemplate: ""
            )
        }
        working = stripNoiseTags(from: working)

        let folded = working.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let alphanumeric = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(alphanumeric))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Removes only the `(...)`/`[...]` groups whose contents are a known
    /// noise term (see `titleNoiseTerms`) — groups containing a real edition
    /// marker (e.g. "(Remix)") are left in place.
    nonisolated private static func stripNoiseTags(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[\(\[]([^()\[\]]+)[\)\]]"#) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let groupRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let inner = result[groupRange].lowercased().trimmingCharacters(in: .whitespaces)
            if titleNoiseTerms.contains(inner) {
                result.removeSubrange(fullRange)
            }
        }
        return result
    }

    /// Matches a trailing "- Topic" (any dash style) — YouTube's
    /// auto-generated "Topic" channel naming convention for official
    /// Content-ID audio (e.g. "WoodenToaster - Topic"). Stripped so the same
    /// track imported once via a Topic-channel download and once from a
    /// plain-artist source (Apple Music, a manual import, a different
    /// extractor version) still compares equal instead of silently evading
    /// both the pre-download dedupe check and the Duplicate Scanner.
    private static let topicChannelSuffixRegex = try? NSRegularExpression(
        pattern: #"(?i)\s*[-–—]\s*Topic\s*$"#
    )

    /// Like `normalize`, but additionally strips a trailing "- Topic" channel
    /// suffix, splits on common multi-artist separators (",", "&", "/", " x ",
    /// " vs ", "with") and sorts the parts — so "Artist A & Artist B" and
    /// "Artist B, Artist A" (or the same pairing tagged with a different
    /// separator across sources) compare equal.
    nonisolated static func normalizeArtist(_ text: String) -> String {
        var working = text
        if let topicChannelSuffixRegex {
            working = topicChannelSuffixRegex.stringByReplacingMatches(
                in: working, range: NSRange(working.startIndex..., in: working), withTemplate: ""
            )
        }
        if let featureClauseRegex {
            working = featureClauseRegex.stringByReplacingMatches(
                in: working, range: NSRange(working.startIndex..., in: working), withTemplate: ""
            )
        }
        guard let separatorRegex = try? NSRegularExpression(pattern: #"(?i)\s*(,|&|/| x | vs\.?\s| with )\s*"#) else {
            return normalize(working)
        }
        let unified = separatorRegex.stringByReplacingMatches(
            in: working, range: NSRange(working.startIndex..., in: working), withTemplate: "|"
        )
        let parts = unified.components(separatedBy: "|")
            .map { normalize($0) }
            .filter { !$0.isEmpty }
            .sorted()
        return parts.joined(separator: " ")
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
    case acousticMatch
    case sameTitleAndArtist

    var label: String {
        switch self {
        case .sameSourceTrack: return "Same source track"
        case .acousticMatch: return "Sounds identical"
        case .sameTitleAndArtist: return "Same title & artist"
        }
    }
}
