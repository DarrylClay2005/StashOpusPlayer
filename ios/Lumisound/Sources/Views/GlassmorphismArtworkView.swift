import SwiftUI

// MARK: - GlassmorphismArtworkView
//
// Album art fills the background of a rounded card. A frosted glass
// (.ultraThinMaterial) panel is overlaid on the lower portion showing
// song title and artist, with a thin accent border around the card.

struct GlassmorphismArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    private let cardSize: CGFloat = 300

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed album art as background
            artBackground

            // Frosted glass info strip at the bottom
            glassInfoStrip
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppTheme.dynamicAccent.opacity(0.35), lineWidth: 1.5)
        )
        .shadow(color: AppTheme.dynamicAccent.opacity(0.3), radius: 22, x: 0, y: 10)
    }

    @ViewBuilder
    private var artBackground: some View {
        if let song {
            ArtworkThumbnail(song: song, size: cardSize)
                .environmentObject(library)
        } else {
            LinearGradient(
                colors: [AppTheme.surface, AppTheme.elevatedSurface, AppTheme.accent.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: cardSize, height: cardSize)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 80, weight: .semibold))
                    .foregroundStyle(AppTheme.accent.opacity(0.6))
            }
        }
    }

    private var glassInfoStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song?.displayName ?? "Nothing Playing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(song?.artistName ?? "—")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        // Clip only the bottom corners to match the card
        .clipShape(
            RoundedCornerShape(radius: 20, corners: [.bottomLeft, .bottomRight])
        )
    }
}

// MARK: - RoundedCornerShape

/// A shape that rounds only the specified corners — used to apply the glass strip
/// only to the bottom corners so the top edge meets the artwork cleanly.
private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
