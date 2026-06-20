import SwiftUI

// MARK: - DepthParallaxArtworkView
//
// A layered "depth card": a large, heavily-blurred copy of the artwork sits
// behind a crisp foreground cover, and the two layers drift in opposite
// directions on a slow loop so the cover appears to float above its own
// out-of-focus backdrop — a parallax depth effect without needing device
// motion. Palette-tinted edge light frames the foreground.

struct DepthParallaxArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var shift: CGFloat = 0

    var body: some View {
        ZStack {
            // Blurred backdrop layer — drifts one way.
            artwork(size: 300)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .blur(radius: 28)
                .opacity(0.7)
                .scaleEffect(1.18)
                .offset(x: shift, y: shift * 0.6)

            // Crisp foreground cover — drifts the other way + palette edge light.
            artwork(size: 230)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.9),
                                    (palette?.secondary ?? AppTheme.accentSoft).opacity(0.4),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.45), radius: 26, x: 0, y: 16)
                .offset(x: -shift * 0.8, y: -shift * 0.5)
        }
        .frame(width: 320, height: 320)
        .onAppear { startDrift(playing: isPlaying) }
        .onChange(of: isPlaying) { startDrift(playing: $0) }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func startDrift(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                shift = 14
            }
        } else {
            withAnimation(.easeOut(duration: 0.7)) { shift = 0 }
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
