import SwiftUI

// MARK: - WatchNowPlayingView
//
// The companion remote UI: artwork + title/artist mirrored from the phone, plus
// previous / play-pause / next transport controls that send commands back.

struct WatchNowPlayingView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager

    var body: some View {
        VStack(spacing: 8) {
            artwork
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(spacing: 1) {
                Text(connectivity.title.isEmpty ? "Nothing Playing" : connectivity.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if !connectivity.artist.isEmpty {
                    Text(connectivity.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 14) {
                transportButton("backward.fill") { connectivity.send(command: "previous") }
                transportButton(connectivity.isPlaying ? "pause.fill" : "play.fill", large: true) {
                    connectivity.send(command: "toggle")
                }
                transportButton("forward.fill") { connectivity.send(command: "next") }
            }
            .padding(.top, 2)

            if !connectivity.reachable {
                Text("Open Lumisound on iPhone")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = connectivity.artworkData, let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.gray.opacity(0.3))
                Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.secondary)
            }
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
