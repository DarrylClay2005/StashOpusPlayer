import SwiftUI

// MARK: - MirrorWallArtworkView
//
// An ambient "wall" of the artwork: a large blurred, tiled/mirrored backdrop
// fills the frame while a single crisp, floating copy sits centered on top —
// an immersive, edge-to-edge presentation reminiscent of full-bleed lock-screen
// art.

struct MirrorWallArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?

    var body: some View {
        ZStack {
            // Full-bleed blurred backdrop (oversized then clipped to the frame).
            artwork(size: 360)
                .frame(width: 320, height: 320)
                .clipped()
                .blur(radius: 38)
                .opacity(0.85)
                .overlay(
                    // Palette tint + darkening so the centered cover stands out.
                    LinearGradient(
                        colors: [
                            (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.18),
                            Color.black.opacity(0.35),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            // Centered crisp cover, floating.
            artwork(size: 210)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 16)
                .modifier(FloatModifier(isPlaying: isPlaying, amount: 7, speed: 3.2))
        }
        .frame(width: 320, height: 320)
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.surface, AppTheme.elevatedSurface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.27, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }
}
