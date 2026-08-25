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

        // Preserve existing artwork if already set (avoid flickering during position updates).
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           let existingArtwork = existing[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existingArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Fetches artwork asynchronously and injects it into the Now Playing info center
    /// and the WidgetKit shared container.
    func updateNowPlayingArtwork(for song: Song?) async {
        guard let song else {
            WidgetDataService.shared.update(song: nil, isPlaying: false, artwork: nil)
            PhoneWatchSync.shared.update(song: nil, isPlaying: false, artwork: nil)
            return
        }
        let image = await ArtworkService.shared.loadArtwork(for: song)
        if let image {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
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
