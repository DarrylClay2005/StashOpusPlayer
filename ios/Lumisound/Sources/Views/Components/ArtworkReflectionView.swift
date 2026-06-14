import SwiftUI

/// A mirrored, fading copy of the artwork rendered below the real artwork —
/// the classic "glass shelf" reflection look. Used by the flatter Now Playing
/// artwork presets (Album Art, Minimalist, Tilt Card) to add depth without
/// any extra animation cost.
struct ArtworkReflectionView: View {
    let song: Song?
    let size: CGFloat
    let cornerRadius: CGFloat

    @EnvironmentObject private var library: LibraryManager

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(y: -1)
            .mask(
                LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
            )
            .frame(height: size * 0.55, alignment: .top)
            .clipped()
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var content: some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.surface, AppTheme.elevatedSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}
