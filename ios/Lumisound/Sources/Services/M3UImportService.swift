import Foundation

/// Parses an `.m3u`/`.m3u8` playlist file and matches its entries against the
/// user's local library, so playlists exported from other apps/libraries
/// (iTunes, VLC, foobar2000, or this app's own `exportM3U()`) can be brought
/// in. Export already existed (`PlaylistDetailView.exportM3U()`); this is the
/// missing other half — there was previously no way to *import* an M3U file.
enum M3UImportService {

    struct ImportResult {
        let matchedSongIDs: [String]
        let totalEntries: Int
    }

    // @MainActor because matching reads `library.allSongs`, and `LibraryManager`
    // is itself main-actor-isolated. File I/O and parsing are cheap for a
    // playlist-sized file, so there's no need to hop off the main actor.

    /// Reads and matches an M3U file's entries against `library`. Matching
    /// order per entry:
    ///  1. Exact filename (last path component, case-insensitive) against a
    ///     song's own file URL — handles the common case of an M3U exported
    ///     by this app, or one referencing files also present in this
    ///     library under the same name.
    ///  2. Title + artist parsed from the preceding `#EXTINF` line, matched
    ///     case-insensitively — handles M3Us built by other apps/devices
    ///     whose file paths don't exist on this device at all.
    /// Entries matching neither are simply skipped; a partial match never
    /// fails the whole import (`ImportResult.totalEntries` lets the caller
    /// report "N of M tracks matched").
    @MainActor
    static func `import`(fileURL: URL, library: LibraryManager) -> ImportResult {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            return ImportResult(matchedSongIDs: [], totalEntries: 0)
        }

        var songsByFilename: [String: Song] = [:]
        for song in library.allSongs {
            guard let name = song.url?.lastPathComponent.lowercased() else { continue }
            if songsByFilename[name] == nil { songsByFilename[name] = song }
        }

        var matchedIDs: [String] = []
        var seenIDs = Set<String>()
        var totalEntries = 0
        var pendingExtinf: (title: String, artist: String)?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF:") {
                // "#EXTINF:<duration>,<Artist> - <Title>" — the convention
                // this app's own exportM3U() (and most other players) write.
                if let comma = line.firstIndex(of: ",") {
                    let info = String(line[line.index(after: comma)...])
                    let parts = info.components(separatedBy: " - ")
                    if parts.count >= 2 {
                        pendingExtinf = (title: parts.dropFirst().joined(separator: " - "), artist: parts[0])
                    } else {
                        pendingExtinf = (title: info, artist: "")
                    }
                }
                continue
            }
            if line.hasPrefix("#") { continue }

            totalEntries += 1
            let extinf = pendingExtinf
            pendingExtinf = nil

            let filename = (line as NSString).lastPathComponent.lowercased()
            var match = songsByFilename[filename]

            if match == nil, let extinf, !extinf.title.isEmpty {
                match = library.allSongs.first {
                    $0.displayName.caseInsensitiveCompare(extinf.title) == .orderedSame
                        && (extinf.artist.isEmpty || $0.artistName.caseInsensitiveCompare(extinf.artist) == .orderedSame)
                }
            }

            if let match, !seenIDs.contains(match.id) {
                matchedIDs.append(match.id)
                seenIDs.insert(match.id)
            }
        }

        return ImportResult(matchedSongIDs: matchedIDs, totalEntries: totalEntries)
    }
}
