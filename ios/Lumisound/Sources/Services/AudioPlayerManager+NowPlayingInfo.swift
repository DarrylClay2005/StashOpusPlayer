@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import MediaPlayer
import UIKit

extension AudioPlayerManager {

    // MARK: - Now Playing / Remote Commands

    func updateNowPlaying() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            nowPlayingArtworkSongID = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.displayName,
            MPMediaItemPropertyArtist: song.artistName,
            MPMediaItemPropertyAlbumTitle: song.albumName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(audioSettings.speed) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(audioSettings.speed)
        ]

        // Preserve artwork during position updates, but never carry artwork
        // over from a different track while the new track's artwork loads.
        if nowPlayingArtworkSongID == song.id,
           let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           let existingArtwork = existing[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existingArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Fetches artwork asynchronously and injects it into the Now Playing info center
    /// and the WidgetKit shared container.
    func updateNowPlayingArtwork(for song: Song?) async {
        guard let song else {
            nowPlayingArtworkSongID = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            WidgetDataService.shared.update(song: nil, isPlaying: false, artwork: nil)
            PhoneWatchSync.shared.update(song: nil, isPlaying: false, artwork: nil)
            return
        }
        let image = await ArtworkService.shared.loadArtwork(for: song)
        // Artwork loads can finish out of order when tracks change quickly.
        // Do not let an older request overwrite the current system controls
        // or shared widget state.
        guard currentSong?.id == song.id else { return }
        if let image {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            nowPlayingArtworkSongID = song.id
        } else {
            nowPlayingArtworkSongID = nil
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
        WidgetDataService.shared.update(
            song: song, isPlaying: isPlaying, artwork: image, position: position, duration: duration,
            isFavorite: LibraryManager.shared?.isFavorite(songID: song.id) ?? false
        )
        PhoneWatchSync.shared.update(song: song, isPlaying: isPlaying, artwork: image)
    }

    func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: e.positionTime) }
            }
            return .success
        }
    }
}
