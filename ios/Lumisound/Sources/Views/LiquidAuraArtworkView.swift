import SwiftUI

// MARK: - LiquidAuraArtworkView — "Lava Lamp"
//
// The cover over big, bright, screen-blended blobs drifting on black — a vivid
// lava-lamp glow.
struct LiquidAuraArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var drift = false

    private var c1: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var c2: Color { palette?.secondary ?? AppTheme.accentSoft }
    private var c3: Color { Color(hue: 0.55, saturation: 0.85, brightness: 0.95) }

    // (size, color, restPos, driftPos)
    private var blobs: [(CGFloat, Color, CGSize, CGSize)] {
        [
            (210, c1, CGSize(width: -80, height: -70), CGSize(width: -45, height: 50)),
            (190, c2, CGSize(width: 90, height: -50),  CGSize(width: 55, height: 80)),
            (180, c3, CGSize(width: 55, height: 100),  CGSize(width: -70, height: 35)),
            (160, c1, CGSize(width: -90, height: 80),  CGSize(width: -35, height: -70)),
            (150, c2, CGSize(width: 0, height: 0),     CGSize(width: 30, height: -30)),
        ]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black)

            ForEach(Array(blobs.enumerated()), id: \.offset) { _, b in
                Circle()
                    .fill(b.1)
                    .frame(width: b.0, height: b.0)
                    .blur(radius: 34)
                    .opacity(isPlaying ? 0.85 : 0.6)
                    .blendMode(.screen)
                    .offset(drift ? b.3 : b.2)
            }

            StyleCover(song: song, size: 230, cornerRadius: 20)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 26, y: 12)
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.2))
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { drift = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
