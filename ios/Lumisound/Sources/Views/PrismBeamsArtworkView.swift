import SwiftUI

// MARK: - PrismBeamsArtworkView — "Neon Trace"
//
// The cover wrapped in a bright neon outline with a strong glow, over a rotating
// conic halo — a vivid nightclub sign.
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
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color.black.opacity(0.25))

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(
                    AngularGradient(colors: [tint, tint2, .white, tint2, tint], center: .center,
                                    angle: .degrees(spin ? 360 : 0)),
                    lineWidth: 42
                )
                .blur(radius: 38)
                .opacity(isPlaying ? 1.0 : 0.6)
                .frame(width: 300, height: 300)

            StyleCover(song: song, size: 278, cornerRadius: 22)
                .clipShape(shape)
                .overlay(shape.stroke(.white, lineWidth: 2.5))
                .overlay(shape.stroke(tint, lineWidth: 6).blur(radius: 5))
                .shadow(color: tint.opacity(glow ? 1.0 : 0.6), radius: glow ? 42 : 24)
                .shadow(color: tint2.opacity(0.7), radius: 30)
        }
        .frame(width: 320, height: 320)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 3.0))
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { glow = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
