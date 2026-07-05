import Foundation
import MediaPlayer
import UIKit

extension LibraryManager {

    // MARK: - Tempo (BPM)

    /// Returns `song.bpm` if already known, otherwise analyzes the track via
    /// `BPMAnalyzerService` (on-device, ffmpeg-equivalent autocorrelation) and
    /// caches the result on the song for future lookups — used by the player
    /// to drive beat-aware crossfades and by any other tempo-aware feature.
    /// Returns `nil` if the song has no local URL or no tempo could be estimated.
    func bpm(for song: Song) async -> Double? {
        if let bpm = song.bpm { return bpm }
        guard let url = song.url else { return nil }

        guard let estimated = await BPMAnalyzerService.shared.bpm(for: url) else { return nil }
        storeBPM(estimated, for: song.id)
        return estimated
    }

    /// Writes a freshly-analyzed BPM back into `mediaSongs`/`importedSongs` so
    /// it's returned instantly next time and survives in the persisted
    /// library snapshot.
    func storeBPM(_ bpm: Double, for songID: String) {
        if let index = mediaSongs.firstIndex(where: { $0.id == songID }) {
            mediaSongs[index].bpm = bpm
        } else if let index = importedSongs.firstIndex(where: { $0.id == songID }) {
            importedSongs[index].bpm = bpm
        } else {
            return
        }
        rebuildAllSongs()
    }
}
