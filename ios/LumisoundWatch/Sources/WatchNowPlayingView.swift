import SwiftUI

// MARK: - WatchNowPlayingView
//
// Transport screen with two distinct modes, chosen automatically:
//  - "Remote" mode (default): mirrors the iPhone's Now Playing state via
//    WatchConnectivityManager and sends transport commands back to the phone.
//    This is the original, unchanged companion-remote behavior.
//  - "Standalone" mode: once a track has been started from the Watch Library
//    (see WatchLibraryView), this same layout instead reflects/controls
//    WatchLocalPlayerManager's own on-watch AVAudioPlayer — no phone required.
// `isStandalone` is the single source of truth for which mode is active, so
// the view (and the user) never has to guess which player it's driving.

struct WatchNowPlayingView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager
    @EnvironmentObject private var player: WatchLocalPlayerManager

    /// A track started from the Watch Library "wins" for the rest of the app
    /// session — standalone playback never touches the phone, so there's no
    /// need to arbitrate between the two beyond this simple flag.
    private var isStandalone: Bool { player.hasActiveTrack }

    var body: some View {
        VStack(spacing: 8) {
            modeLabel

            artwork
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(spacing: 1) {
                Text(titleText.isEmpty ? "Nothing Playing" : titleText)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if !artistText.isEmpty {
                    Text(artistText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if isStandalone {
                Slider(
                    value: Binding(
                        get: { player.position },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .frame(height: 14)
                .tint(connectivity.accentColor)
            }

            HStack(spacing: 14) {
                transportButton("backward.fill") { previous() }
                transportButton(isPlayingNow ? "pause.fill" : "play.fill", large: true) { togglePlayPause() }
                transportButton("forward.fill") { next() }
            }
            .padding(.top, 2)
            .tint(connectivity.accentColor)

            if !isStandalone && !connectivity.reachable {
                Text("Open Lumisound on iPhone")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: Mode-dependent state

    private var titleText: String { isStandalone ? (player.currentTrack?.title ?? "") : connectivity.title }
    private var artistText: String { isStandalone ? (player.currentTrack?.artist ?? "") : connectivity.artist }
    private var isPlayingNow: Bool { isStandalone ? player.isPlaying : connectivity.isPlaying }

    @ViewBuilder
    private var modeLabel: some View {
        if isStandalone {
            Text("WATCH LIBRARY")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        // Standalone tracks don't fetch artwork (kept out of scope to keep the
        // local player simple — see WatchTrack.hasArtwork, currently unused).
        if !isStandalone, let data = connectivity.artworkData, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.gray.opacity(0.3))
                Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions — routed to whichever player is active

    private func togglePlayPause() {
        if isStandalone {
            player.togglePlayPause()
        } else {
            connectivity.send(command: "toggle")
        }
    }

    private func previous() {
        if isStandalone {
            player.skipPrevious()
        } else {
            connectivity.send(command: "previous")
        }
    }

    private func next() {
        if isStandalone {
            player.skipNext()
        } else {
            connectivity.send(command: "next")
        }
    }

    private func transportButton(_ symbol: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 22 : 16, weight: .semibold))
                .frame(width: large ? 44 : 34, height: large ? 44 : 34)
        }
        .buttonStyle(.plain)
    }
}
