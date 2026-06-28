import SwiftUI

// MARK: - PrismBeamsArtworkView — "Neon Trace"
//
// The cover ringed by a glowing neon outline that pulses, over a slowly-rotating
// conic glow — a nightclub-sign look.
struct PrismBeamsArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var spin = false
    @State private var glow = false

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private var tint: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var tint2: Color { palette?.secondary ?? AppTheme.accentSoft }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(
                    AngularGradient(colors: [tint, tint2, .white, tint], center: .center,
                                    angle: .degrees(spin ? 360 : 0)),
                    lineWidth: 36
                )
                .blur(radius: 34)
                .opacity(isPlaying ? 0.9 : 0.5)
                .frame(width: 300, height: 300)

            StyleCover(song: song, size: 280, cornerRadius: 22)
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.9), lineWidth: 2))
                .overlay(shape.stroke(tint, lineWidth: 4).blur(radius: 4))
                .shadow(color: tint.opacity(glow ? 0.95 : 0.5), radius: glow ? 34 : 16)
        }
        .frame(width: 320, height: 320)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 3.0))
        .onAppear {
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
