import SwiftUI

// MARK: - AlbumArtworkView — "Aurora Veil"
//
// The cover over a vivid, full-frame aurora: bright screen-blended colour bands
// drifting on a deep night base.
struct AlbumArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var drift = false

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    private var c1: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var c2: Color { palette?.secondary ?? AppTheme.accentSoft }
    private var bands: [Color] { [c1, Color(hue: 0.45, saturation: 0.8, brightness: 0.95), c2, Color(hue: 0.78, saturation: 0.7, brightness: 0.95)] }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.04, green: 0.04, blue: 0.10))

            ForEach(0..<4) { i in
                Ellipse()
                    .fill(bands[i])
                    .frame(width: 320, height: 140)
                    .rotationEffect(.degrees(-22 + Double(i) * 12 + (drift ? 10 : -10)))
                    .offset(x: drift ? CGFloat(i * 16 - 24) : CGFloat(-i * 16 + 24),
                            y: CGFloat(i - 2) * 58 + (drift ? 18 : -18))
                    .blur(radius: 34)
                    .opacity(isPlaying ? 0.8 : 0.6)
                    .blendMode(.screen)
            }

            StyleCover(song: song, size: 250, cornerRadius: 20)
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 22, y: 14)
                .shadow(color: c1.opacity(0.4), radius: 30)
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 3.0))
        .onAppear {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { drift = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
