import SwiftUI

// MARK: - HolographicArtworkView
//
// Treats the cover like a holographic foil trading card: a rainbow iridescent
// wash (angular gradient, screen-blended) rotates slowly over the art, and a
// bright specular "sheen" band sweeps diagonally across while playing — the
// telltale tilt-the-card-in-the-light effect. Distinct from every other style
// in that the effect is an iridescent material on the artwork itself.

struct HolographicArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var hueRotate: Double = 0
    @State private var sheen: CGFloat = -1.4

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        artwork(size: 280)
            .clipShape(shape)
            // Iridescent rainbow wash, screen-blended and rotating.
            .overlay(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                    center: .center,
                    angle: .degrees(hueRotate)
                )
                .blendMode(.screen)
                .opacity(0.35)
                .clipShape(shape)
            )
            // Diagonal specular sheen sweeping across.
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.7), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .rotationEffect(.degrees(22))
                    .offset(x: sheen * geo.size.width)
                    .blendMode(.plusLighter)
                }
                .clipShape(shape)
            )
            .overlay(shape.stroke(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.4), radius: 22, x: 0, y: 10)
            .frame(width: 320, height: 320)
            .onAppear { animate(playing: isPlaying) }
            .onChange(of: isPlaying) { animate(playing: $0) }
            .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                hueRotate = 360
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false)) {
                sheen = 1.4
            }
        } else {
            withAnimation(.easeOut(duration: 0.6)) { sheen = 0.0 }
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
