import Foundation

extension LibraryManager {
    /// Relinks `songID`'s source (see `DeadLinkHealingService`) — updates
    /// both the in-memory `Song.sourceTrackID` and the on-disk vault xattr
    /// tag itself (`LumisoundTrackTagger.tag`), so the new link survives a
    /// rescan (`sourceTrackID` is reconstructed from that tag at scan time,
    /// not persisted any other way — see `LumisoundTrackTagger.readTag`).
    /// Does NOT touch the file's audio bytes or re-download anything — this
    /// only repairs which upstream source a *future* re-download would use;
    /// the current local file (already playable) is untouched.
    @discardableResult
    func updateSourceTrackID(songID: String, to newSourceTrackID: String) -> Bool {
        guard let index = importedSongs.firstIndex(where: { $0.id == songID }),
              let url = importedSongs[index].url,
              let colon = newSourceTrackID.firstIndex(of: ":") else { return false }

        let source = String(newSourceTrackID[newSourceTrackID.startIndex..<colon])
        let bareID = String(newSourceTrackID[newSourceTrackID.index(after: colon)...])
        let sourceURL: String
        switch source {
        case "youtube": sourceURL = "https://youtube.com/watch?v=\(bareID)"
        default: return false
        }

        guard LumisoundTrackTagger.tag(fileURL: url, trackID: newSourceTrackID, sourceURL: sourceURL) else { return false }
        importedSongs[index].sourceTrackID = newSourceTrackID
        rebuildAllSongs()
        return true
    }
}
