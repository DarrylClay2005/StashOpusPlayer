import Foundation

// MARK: - PodcastDownloadManager
//
// Offline downloads for podcast episodes — a natural follow-up to
// PodcastsView/PodcastEpisodesView (streaming-only until now). An episode's
// enclosure URL is already a direct, playable audio file (unlike YouTube
// tracks, which need yt-dlp), so this is a plain `URLSession.downloadTask`
// straight to disk — no download-job/queue infrastructure from the music
// pipeline is reused or needed here.
///
/// Deliberately v1-simple: no granular download percentage (would need a
/// `URLSessionDownloadDelegate` for byte-level progress callbacks) — just
/// downloading/downloaded/not-downloaded state, shown as an indeterminate
/// spinner while in flight. Good enough for a typical single-episode-at-a-
/// time download; a progress bar can be added later without changing this
/// type's public surface.
@MainActor
final class PodcastDownloadManager: ObservableObject {
    static let shared = PodcastDownloadManager()

    @Published private(set) var downloadedGuids: Set<String> = []
    @Published private(set) var downloadingGuids: Set<String> = []

    private let directory: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("PodcastDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        refreshDownloadedGuids()
    }

    /// The local file URL an episode WOULD be saved to — reversible from an
    /// arbitrary guid (which some feeds set to a full URL, not a short id)
    /// via percent-encoding, so `refreshDownloadedGuids` can recover the
    /// original guid back from the filename on disk without a separate
    /// manifest file.
    private func fileURL(for guid: String) -> URL {
        let safe = guid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return directory.appendingPathComponent("\(safe).audio")
    }

    /// Returns the local file if `guid` has been downloaded, `nil`
    /// otherwise — callers (PodcastEpisodesView.play) use this to prefer
    /// the local copy over streaming when available.
    func localURL(for guid: String) -> URL? {
        let url = fileURL(for: guid)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(_ guid: String) -> Bool { downloadedGuids.contains(guid) }
    func isDownloading(_ guid: String) -> Bool { downloadingGuids.contains(guid) }

    func download(episode: PodcastEpisode) {
        guard !downloadedGuids.contains(episode.guid),
              !downloadingGuids.contains(episode.guid),
              let remoteURL = URL(string: episode.audioURL) else { return }

        downloadingGuids.insert(episode.guid)
        let destination = fileURL(for: episode.guid)
        let guid = episode.guid

        let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.downloadingGuids.remove(guid)
                guard let tempURL, error == nil else {
                    appWarn("PodcastDownloadManager: download failed for \(guid): \(error?.localizedDescription ?? "no temp file")", category: "network")
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    self.downloadedGuids.insert(guid)
                } catch {
                    appWarn("PodcastDownloadManager: couldn't save download for \(guid): \(error.localizedDescription)", category: "network")
                }
            }
        }
        task.resume()
    }

    func deleteDownload(guid: String) {
        try? FileManager.default.removeItem(at: fileURL(for: guid))
        downloadedGuids.remove(guid)
    }

    private func refreshDownloadedGuids() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        var guids: Set<String> = []
        for file in files {
            let encodedName = file.deletingPathExtension().lastPathComponent
            if let decoded = encodedName.removingPercentEncoding {
                guids.insert(decoded)
            }
        }
        downloadedGuids = guids
    }
}
