import SwiftUI

// MARK: - TiltCardArtworkView — "Depth Parallax"
//
// A layered 3D scene: a palette back-card and the cover front-card tilt by
// different amounts, so the colour layer parallaxes out behind the art for real
// depth, with a tracking glare and deep shadow.
struct TiltCardArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var tilt = false

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private var c1: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var c2: Color { palette?.secondary ?? AppTheme.accentSoft }

    var body: some View {
        ZStack {
            // Back accent card — tilts MORE and offsets MORE (parallax depth).
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 288, height: 288)
                .rotation3DEffect(.degrees(tilt ? 16 : -16), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .offset(x: tilt ? 24 : -24, y: 12)
                .opacity(0.75)
                .blur(radius: 2)

            // Soft cast shadow under the front card.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.45))
                .frame(width: 270, height: 270)
                .offset(x: tilt ? 12 : -12, y: 20)
                .blur(radius: 14)

            // Front cover — tilts LESS.
            StyleCover(song: song, size: 270, cornerRadius: 22)
                .clipShape(shape)
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.4), .clear, .white.opacity(0.12)],
                                   startPoint: tilt ? .topLeading : .bottomTrailing,
                                   endPoint: tilt ? .bottomTrailing : .topLeading)
                        .blendMode(.plusLighter)
                        .clipShape(shape)
                )
                .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 1))
                .rotation3DEffect(.degrees(tilt ? 8 : -8), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(tilt ? -8 : 8), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        }
        .frame(width: 330, height: 330)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { tilt = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
