import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .frame(width: 40, height: 40)
                    .background(AppTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(song.artistName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    player.skipToPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                }

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)

                Button {
                    player.skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}
