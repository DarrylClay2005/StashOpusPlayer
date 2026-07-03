import SwiftUI

// MARK: - RippleArtworkView — "Halo Pulse"
//
// A circular cover over a bright radial glow, ringed by thick palette-tinted
// halos that pulse outward.
struct RippleArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var pulse = false

    private var tint: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var tint2: Color { palette?.secondary ?? AppTheme.accentSoft }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0.0)],
                                     center: .center, startRadius: 50, endRadius: 180))
                .frame(width: 330, height: 330)

            ForEach(0..<4) { i in
                Circle()
                    .stroke(
                        LinearGradient(colors: [tint, tint2], startPoint: .top, endPoint: .bottom)
                            .opacity(pulse ? 0.15 : 0.9),
                        lineWidth: 4
                    )
                    .frame(width: 240 + CGFloat(i) * 28, height: 240 + CGFloat(i) * 28)
                    .scaleEffect(pulse ? 1.14 : 0.9)
                    .animation(
                        .easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(Double(i) * 0.35),
                        value: pulse
                    )
            }

            StyleCover(song: song, size: 230, cornerRadius: 115)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1.5))
                .shadow(color: tint.opacity(0.6), radius: 30)
        }
        .frame(width: 330, height: 330)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 3.0))
        .onAppear { pulse = isPlaying }
        .onChange(of: isPlaying) { pulse = $0 }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
