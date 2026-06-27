import SwiftUI

// MARK: - RippleArtworkView — "Halo Pulse"
//
// A circular cover surrounded by breathing, palette-tinted halo rings.
struct RippleArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var pulse = false

    private var tint: Color { palette?.primary ?? AppTheme.dynamicAccent }

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(tint.opacity(pulse ? 0.12 : 0.5), lineWidth: 3)
                    .frame(width: 250 + CGFloat(i) * 26, height: 250 + CGFloat(i) * 26)
                    .scaleEffect(pulse ? 1.12 : 0.92)
                    .animation(
                        .easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(Double(i) * 0.4),
                        value: pulse
                    )
            }

            StyleCover(song: song, size: 240, cornerRadius: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: tint.opacity(0.5), radius: 26)
        }
        .frame(width: 330, height: 330)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 3.0))
        .onAppear { pulse = isPlaying }
        .onChange(of: isPlaying) { pulse = $0 }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
