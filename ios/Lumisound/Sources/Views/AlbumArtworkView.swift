import SwiftUI

// MARK: - AlbumArtworkView — "Aurora Veil"
//
// The cover floats over slow-drifting aurora ribbons tinted from the artwork
// palette — a calm, modern, ambient presentation.
struct AlbumArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var drift = false

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private var c1: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var c2: Color { palette?.secondary ?? AppTheme.accentSoft }

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, (i == 1 ? c2 : c1).opacity(0.6), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 380, height: 110)
                    .rotationEffect(.degrees(Double(i - 1) * 26 + (drift ? 7 : -7)))
                    .offset(x: drift ? 18 : -18, y: CGFloat(i - 1) * 78)
                    .blur(radius: 30)
                    .opacity(isPlaying ? 0.95 : 0.55)
            }

            StyleCover(song: song, size: 290, cornerRadius: 22)
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 26, y: 16)
                .shadow(color: c1.opacity(0.35), radius: 34)
        }
        .frame(width: 330, height: 330)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 7, speed: 3.0))
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { drift = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
