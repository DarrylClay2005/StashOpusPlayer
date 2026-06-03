import SwiftUI

struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    var showArtwork: Bool = true
    var subtitle: String? = nil

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    private var resolvedSubtitle: String {
        subtitle ?? "\(song.artistName) · \(song.albumName)"
    }

    var body: some View {
        HStack(spacing: 12) {
            if showArtwork {
                ArtworkThumbnail(song: song, size: 44)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AppTheme.accent.opacity(0.7))
                            WaveformIcon()
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayName)
                    .foregroundStyle(isCurrent ? AppTheme.accent : AppTheme.textPrimary)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)

                Text(resolvedSubtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(song.durationText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .contextMenu {
            SongContextMenuContent(song: song)
                .environmentObject(library)
                .environmentObject(player)
        }
    }
}

// Animated waveform bars shown when a song is current
private struct WaveformIcon: View {
    @State private var animating = false

    private let heights: [CGFloat] = [0.45, 0.85, 0.60, 0.80, 0.50]
    private let delays: [Double]   = [0.0,  0.15, 0.30, 0.10, 0.25]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.textPrimary)
                    .frame(width: 3, height: animating ? 14 * heights[i] : 4)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(delays[i]),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
