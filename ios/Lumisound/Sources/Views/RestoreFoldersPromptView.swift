import SwiftUI

// MARK: - RestoreFoldersPromptView
//
// Detects a "returning user, first login on this install" scenario — the
// local watched-folders list (`MusicFolderService.watchedFolders`) is empty,
// but the server has a folder-structure backup (`ios_user_folder_backups`,
// pushed by a previous install via `AccountService.pushFolderBackups`) — and
// offers to recreate the original folder layout under Documents, redownloading
// any tracks that have a `source_track_id` (re-fetchable via yt-dlp). Tracks
// without one (local-only imports) get an empty folder recreated so future
// imports land in the right place, and are reported to the user via toast.
//
// Invisible/no-op for everyone else: logged-out users, users with existing
// watched folders, users who've already been prompted this install, or users
// with no folder backup on the server.

struct RestoreFoldersPromptView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var folderService: MusicFolderService
    @EnvironmentObject private var streaming: StreamingService

    @State private var pendingFolders: [FolderBackupEntry]?
    @State private var isRestoring = false

    /// Persists across launches so the prompt is only ever shown once per
    /// install — if the user says "No", we don't nag them again every launch.
    private static let promptedKey = "restoreFoldersPrompt_shownForInstall"

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                await checkForFolderBackup()
            }
            .alert(
                "Restore Your Folders?",
                isPresented: Binding(
                    get: { pendingFolders != nil },
                    set: { if !$0 { pendingFolders = nil } }
                )
            ) {
                Button("Not Now", role: .cancel) {
                    pendingFolders = nil
                }
                Button("Restore") {
                    if let folders = pendingFolders {
                        pendingFolders = nil
                        Task { await restoreFolders(folders) }
                    }
                }
            } message: {
                Text("We found backed-up folders from your library. Would you like Lumisound to redownload your tracks and restore them into their original folders?")
            }
    }

    // MARK: - Detection

    private func checkForFolderBackup() async {
        guard account.isLoggedIn else { return }
        guard folderService.watchedFolders.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: Self.promptedKey) else { return }

        let folders = await account.fetchFolderBackups()
        guard !folders.isEmpty else { return }

        UserDefaults.standard.set(true, forKey: Self.promptedKey)
        pendingFolders = folders
        appLog("RestoreFoldersPromptView: found \(folders.count) backed-up folder(s)", category: "library")
    }

    // MARK: - Restore

    private func restoreFolders(_ folders: [FolderBackupEntry]) async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        var restoredCount = 0
        var failedCount = 0
        var unrecoverableTitles: [String] = []

        for entry in folders {
            guard let folderURL = folderService.recreateFolder(relativePath: entry.folderPath) else {
                appWarn("restoreFolders: could not create folder \(entry.folderPath)", category: "library")
                failedCount += entry.tracks.count
                continue
            }

            for track in entry.tracks {
                guard let streamTrack = streamTrack(for: track) else {
                    // No way to re-fetch this track's audio (local-only import,
                    // or a source we can't redownload from by ID alone) — the
                    // empty folder has still been created so future imports
                    // land in the right place.
                    unrecoverableTitles.append(track.title ?? track.filename)
                    continue
                }

                do {
                    // existingSongs enables downloadToLibrary's pre-download dedupe
                    // (matches by sourceTrackID against a valid on-disk file) — without
                    // it, every track here re-downloads via yt-dlp unconditionally even
                    // if it already exists elsewhere in the library (a different folder,
                    // a prior partial restore), wasting a full yt-dlp fetch that's
                    // discarded the moment the file lands somewhere already covered.
                    _ = try await streaming.downloadToLibrary(track: streamTrack, destinationDir: folderURL, existingSongs: library.allSongs)
                    restoredCount += 1
                } catch {
                    appWarn("restoreFolders: redownload failed for \"\(streamTrack.title)\": \(error.localizedDescription)", category: "library")
                    failedCount += 1
                    unrecoverableTitles.append(track.title ?? track.filename)
                }
            }
        }

        // Re-register the recreated folders with MusicFolderService so they're
        // watched going forward, then rescan to pick up the redownloaded files.
        for entry in folders {
            if let url = folderService.recreateFolder(relativePath: entry.folderPath) {
                try? folderService.addFolder(url: url)
            }
        }
        library.scanWatchedFolders(using: folderService)
        library.scanLocalDocuments()

        if restoredCount > 0 && failedCount == 0 && unrecoverableTitles.isEmpty {
            ToastCenter.shared.show(
                "Restored \(restoredCount) track\(restoredCount == 1 ? "" : "s") into \(folders.count) folder\(folders.count == 1 ? "" : "s")",
                category: .success,
                icon: "folder.fill.badge.gearshape"
            )
        } else if restoredCount > 0 {
            ToastCenter.shared.show(
                "Restored \(restoredCount) track\(restoredCount == 1 ? "" : "s"); \(unrecoverableTitles.count + failedCount) couldn't be auto-restored",
                category: .warning,
                icon: "exclamationmark.triangle.fill"
            )
        } else if !unrecoverableTitles.isEmpty || failedCount > 0 {
            ToastCenter.shared.show(
                "Recreated your folders, but \(unrecoverableTitles.count + failedCount) track\((unrecoverableTitles.count + failedCount) == 1 ? "" : "s") couldn't be auto-restored — re-add them manually",
                category: .warning,
                icon: "folder.badge.questionmark"
            )
        } else {
            ToastCenter.shared.show("Restored your folder structure", category: .success, icon: "folder.fill")
        }

        appLog("restoreFolders: complete (restored=\(restoredCount), failed=\(failedCount), unrecoverable=\(unrecoverableTitles.count))", category: "library")
    }

    /// Builds a `StreamTrack` for redownload from a backed-up track's
    /// `source_track_id` (format "<source>:<id>", e.g. "youtube:dQw4w9WgXcQ").
    /// Returns nil for tracks with no source ID (local-only imports) or sources
    /// that can't be redownloaded by ID alone (e.g. SoundCloud requires a full
    /// URL that isn't recoverable from the ID).
    private func streamTrack(for track: FolderBackupTrack) -> StreamTrack? {
        guard let sourceID = track.sourceTrackID, !sourceID.isEmpty else { return nil }
        let parts = sourceID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let source = parts[0]
        let id = parts[1]

        guard source == "youtube" else {
            // SoundCloud (and any other future sources) need a full track URL
            // to redownload, which isn't stored in the folder backup.
            return nil
        }

        return StreamTrack(
            id: id,
            title: track.title ?? track.filename,
            artist: track.artist ?? "",
            durationSeconds: Int(track.durationSeconds ?? 0),
            thumbnailURL: "",
            source: source,
            youtubeURL: "https://youtube.com/watch?v=\(id)"
        )
    }
}
