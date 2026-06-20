import SwiftUI

// MARK: - AlbumArtworkView
//
// A premium "gallery" presentation of the cover: a soft palette-colored glow
// backplate, the crisp cover with a layered drop shadow and a slow specular
// sheen sweep, and a fading floor reflection — gently floating while playing.
// A polished, modern take on the plain framed cover.

struct AlbumArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var sheen: CGFloat = -1.3

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Palette glow backplate.
                shape
                    .fill(palette?.primary ?? AppTheme.dynamicAccent)
                    .frame(width: 300, height: 300)
                    .blur(radius: 44)
                    .opacity(isPlaying ? 0.45 : 0.28)

                artwork(size: 300)
                    .clipShape(shape)
                    .overlay(
                        // Slow specular sheen sweeping across the cover.
                        GeometryReader { geo in
                            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: geo.size.width * 0.4)
                                .rotationEffect(.degrees(20))
                                .offset(x: sheen * geo.size.width)
                                .blendMode(.plusLighter)
                        }
                        .clipShape(shape)
                    )
                    .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 16)
                    .shadow(color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.35), radius: 30, x: 0, y: 0)
            }

            ArtworkReflectionView(song: song, size: 300, cornerRadius: 18)
                .environmentObject(library)
        }
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 2.8))
        .onAppear { animate(playing: isPlaying) }
        .onChange(of: isPlaying) { animate(playing: $0) }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: false)) { sheen = 1.3 }
        } else {
            withAnimation(.easeOut(duration: 0.6)) { sheen = 0 }
        }
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
