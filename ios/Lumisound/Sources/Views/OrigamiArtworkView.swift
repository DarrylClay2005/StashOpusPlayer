import SwiftUI

// MARK: - SpotlightBeam

private struct SpotlightBeam: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - OrigamiArtworkView — "Spotlight Stage"
//
// The cover on a dark stage lit by two bright spotlight cones that slowly sweep,
// with a palette glow and a fading floor reflection.
struct OrigamiArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var sweep = false

    private var tint: Color { palette?.primary ?? AppTheme.dynamicAccent }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [.black, Color(white: 0.09)], startPoint: .top, endPoint: .bottom))

            ForEach(0..<2) { i in
                SpotlightBeam()
                    .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.04), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 150, height: 300)
                    .rotationEffect(.degrees((i == 0 ? -1 : 1) * (sweep ? 12 : 22)), anchor: .top)
                    .offset(x: i == 0 ? -34 : 34, y: -18)
                    .blur(radius: 9)
                    .blendMode(.plusLighter)
            }

            VStack(spacing: 4) {
                StyleCover(song: song, size: 220, cornerRadius: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: tint.opacity(0.6), radius: 30)
                    .shadow(color: .white.opacity(0.25), radius: 14)

                ArtworkReflectionView(song: song, size: 220, cornerRadius: 16)
                    .environmentObject(library)
            }
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.2))
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { sweep = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
