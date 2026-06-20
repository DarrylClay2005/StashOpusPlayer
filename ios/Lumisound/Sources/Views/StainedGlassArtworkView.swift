import SwiftUI

// MARK: - StainedGlassArtworkView
//
// The cover viewed through a stained-glass window: a lattice of tinted glass
// cells (each a translucent palette wash so the art shows through) separated by
// dark "lead" lines, with a soft light bloom drifting across the panes while
// playing. A decorative, architectural look unlike anything else in the set.

struct StainedGlassArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var bloom: CGFloat = -1

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private let cells = 5

    var body: some View {
        artwork(size: 288)
            .clipShape(shape)
            // Tinted glass cells + lead lines.
            .overlay(
                Canvas { context, size in
                    drawGlass(context: context, size: size)
                }
                .clipShape(shape)
            )
            // Light bloom drifting diagonally across the panes.
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.5), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: geo.size.width * 0.6)
                    .rotationEffect(.degrees(35))
                    .offset(x: bloom * geo.size.width, y: 0)
                    .blendMode(.plusLighter)
                }
                .clipShape(shape)
            )
            .overlay(shape.stroke(.black.opacity(0.55), lineWidth: 4))   // frame "came"
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
            .frame(width: 320, height: 320)
            .onAppear { animate(playing: isPlaying) }
            .onChange(of: isPlaying) { animate(playing: $0) }
            .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
    }

    private func drawGlass(context: GraphicsContext, size: CGSize) {
        let cw = size.width / CGFloat(cells)
        let ch = size.height / CGFloat(cells)
        let primary = palette?.primary ?? AppTheme.dynamicAccent
        let secondary = palette?.secondary ?? AppTheme.accentSoft
        var rng = SeededRandom(seed: 0x57A1)

        // Tint each cell a translucent glass color (art shows through).
        for r in 0..<cells {
            for c in 0..<cells {
                let pick = rng.nextDouble()
                let tint = pick < 0.5 ? primary : secondary
                let alpha = 0.10 + rng.nextDouble() * 0.16
                let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw, height: ch)
                context.fill(Path(rect), with: .color(tint.opacity(alpha)))
            }
        }

        // Dark "lead" lines between cells.
        let lead = Color.black.opacity(0.55)
        for i in 1..<cells {
            var v = Path()
            v.move(to: CGPoint(x: CGFloat(i) * cw, y: 0))
            v.addLine(to: CGPoint(x: CGFloat(i) * cw, y: size.height))
            context.stroke(v, with: .color(lead), lineWidth: 3)

            var h = Path()
            h.move(to: CGPoint(x: 0, y: CGFloat(i) * ch))
            h.addLine(to: CGPoint(x: size.width, y: CGFloat(i) * ch))
            context.stroke(h, with: .color(lead), lineWidth: 3)
        }
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: false)) { bloom = 1.4 }
        } else {
            withAnimation(.easeOut(duration: 0.6)) { bloom = 0 }
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
