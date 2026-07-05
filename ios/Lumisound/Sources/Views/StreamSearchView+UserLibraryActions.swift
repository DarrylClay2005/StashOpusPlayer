import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — User Library Actions

    func handleUserLibraryPlay(track: UserMusicTrack) {
        guard let token = account.token else { return }
        let song = streaming.toSong(userMusicTrack: track, token: token)
        player.play(song: song, in: streaming.userMusicTracks.map { streaming.toSong(userMusicTrack: $0, token: token) })
    }

    func handleUserLibraryDelete(track: UserMusicTrack) {
        guard let token = account.token else { return }
        deletingUserTrackPath = track.serverPath
        Task {
            do {
                try await streaming.deleteUserMusic(path: track.serverPath, token: token)
                await streaming.fetchUserMusic(token: token)
                ToastCenter.shared.show("Deleted \"\(track.title)\" from cloud", category: .info, icon: "trash")
            } catch StreamingError.httpError(404) {
                // Already gone on the server — treat as a successful delete.
                await streaming.fetchUserMusic(token: token)
                ToastCenter.shared.show("Deleted \"\(track.title)\" from cloud", category: .info, icon: "trash")
            } catch {
                streaming.errorMessage = "Delete failed: \(error.localizedDescription)"
                ToastCenter.shared.show("Failed to delete \"\(track.title)\"", category: .error)
            }
            deletingUserTrackPath = nil
        }
    }
}
