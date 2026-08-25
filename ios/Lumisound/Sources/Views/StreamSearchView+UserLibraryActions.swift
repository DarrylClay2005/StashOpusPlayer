import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — User Library Actions

    func handleUserLibraryPlay(track: UserMusicTrack) {
        guard let token = account.token else { return }
        // The queue (everything else in the library, for skip/next) stays on
        // the cheap synchronous path — see toSong's doc comment for the known
        // gap that leaves. The tapped track itself is guaranteed playable:
        // toPlayableSong downloads+unlocks it first if it's a locked backup.
        let queue = streaming.userMusicTracks.map { streaming.toSong(userMusicTrack: $0, token: token) }
        Task {
            let song = await streaming.toPlayableSong(userMusicTrack: track, token: token)
            player.play(song: song, in: queue)
        }
    }

    func handleUserLibraryDelete(track: UserMusicTrack) {
        guard let token = account.token else { return }
        deletingUserTrackPath = track.serverPath
        Task {
            do {
                try await streaming.deleteUserMusic(path: track.serverPath, token: token)
                await streaming.fetchUserMusic(token: token)
                await streaming.fetchStorageUsage(token: token)
                ToastCenter.shared.show("Deleted \"\(track.title)\" from cloud", category: .info, icon: "trash")
            } catch StreamingError.httpError(404) {
                // Already gone on the server — treat as a successful delete.
                await streaming.fetchUserMusic(token: token)
                await streaming.fetchStorageUsage(token: token)
                ToastCenter.shared.show("Deleted \"\(track.title)\" from cloud", category: .info, icon: "trash")
            } catch {
                streaming.errorMessage = "Delete failed: \(error.localizedDescription)"
                ToastCenter.shared.show("Failed to delete \"\(track.title)\"", category: .error)
            }
            deletingUserTrackPath = nil
        }
    }
}
