import AVFoundation
import SwiftUI

// MARK: - TrueMotionArtworkView — "True Motion"
//
// Real animated artwork, matching what Apple Music's own "Animated Artwork"
// actually is: a short, silent, looping video of the release itself — not
// one of this app's 24 generated visual effects (Kaleidoscope Bloom, Aurora
// Veil, etc., all still available as their own styles). For a track sourced
// from YouTube, the closest genuine equivalent is that same video's own
// opening seconds, muted and square-cropped — see `/api/motion-artwork` in
// main.py and `MotionArtworkService` for how it's fetched/cached.
//
// Not every track has this available (SoundCloud/Bandcamp sources, local
// imports, or a YouTube source the server couldn't extract from at all) —
// this always falls back to the plain static `StyleCover` rather than
// showing nothing, per the "real feature or graceful fallback, never a
// placeholder" rule this whole feature exists under.
struct TrueMotionArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var account: AccountService

    @State private var clipURL: URL?
    @State private var loadedForSongID: String?

    private let size: CGFloat = 300
    private let cornerRadius: CGFloat = 24

    var body: some View {
        Group {
            if let clipURL {
                LoopingMutedVideoView(url: clipURL, isPlaying: isPlaying)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
            } else {
                StyleCover(song: song, size: size, cornerRadius: cornerRadius)
                    .environmentObject(library)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
            }
        }
        .task(id: song?.id) {
            await loadClipIfNeeded()
        }
    }

    private var videoID: String? {
        guard let sourceTrackID = song?.sourceTrackID, sourceTrackID.hasPrefix("youtube:") else { return nil }
        let id = String(sourceTrackID.dropFirst("youtube:".count))
        return id.isEmpty ? nil : id
    }

    private func loadClipIfNeeded() async {
        guard let song, song.id != loadedForSongID else { return }
        loadedForSongID = song.id
        guard let videoID else {
            clipURL = nil
            return
        }
        let result = await MotionArtworkService.shared.clipURL(
            videoID: videoID,
            bridgeURL: account.bridgeURL,
            token: account.token
        )
        // The user may have skipped tracks while this was fetching — don't
        // show a stale clip for whatever's playing now.
        guard song.id == loadedForSongID, self.song?.id == song.id else { return }
        clipURL = result
    }
}

/// Bare `AVPlayerLayer` wrapper — deliberately not AVKit's `VideoPlayer`,
/// which shows tap-to-reveal playback controls (play/pause/fullscreen) that
/// have no place on what's meant to read as a static artwork slot that
/// happens to move, not a video player. Loops via
/// `AVPlayerItemDidPlayToEndTime` rather than `AVPlayerLooper`/
/// `AVQueuePlayer` — the clip is already trimmed short server-side, so the
/// brief seek-to-zero gap on loop is not worth the extra queue-player
/// complexity for.
private struct LoopingMutedVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.currentURL = url
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        view.player = player
        context.coordinator.observeLooping(for: player)
        if isPlaying { player.play() }
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        guard uiView.currentURL != url else {
            isPlaying ? uiView.player?.play() : uiView.player?.pause()
            return
        }
        // Track changed to a different clip — swap the player rather than
        // reusing the old AVPlayerItem.
        uiView.currentURL = url
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        uiView.player = player
        context.coordinator.observeLooping(for: player)
        if isPlaying { player.play() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var observer: NSObjectProtocol?

        func observeLooping(for player: AVPlayer) {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

private final class PlayerLayerView: UIView {
    var currentURL: URL?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var player: AVPlayer? {
        get { (layer as? AVPlayerLayer)?.player }
        set {
            (layer as? AVPlayerLayer)?.player = newValue
            (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        }
    }
}
