import SwiftUI

// MARK: - OrigamiArtworkView
//
// The cover seen through a folded-paper / low-poly facet mesh: the artwork is
// overlaid with a grid of triangular facets, each catching light differently
// from a slowly-shifting source — a crystalline, origami-like surface that
// shimmers while playing. Distinct from any flat-card style.

struct OrigamiArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?

    private let artSize: CGFloat = 280
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    private let cols = 6
    private let rows = 6

    var body: some View {
        artwork(size: artSize)
            .clipShape(shape)
            .overlay(
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                    Canvas { context, size in
                        let t = isPlaying ? timeline.date.timeIntervalSinceReferenceDate : 0.6
                        drawFacets(context: context, size: size, time: t)
                    }
                }
                .clipShape(shape)
            )
            .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.35), radius: 22, x: 0, y: 12)
            .shadow(color: .black.opacity(0.4), radius: 14, x: 0, y: 8)
            .frame(width: 320, height: 320)
            .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.0))
            .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
            .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func drawFacets(context: GraphicsContext, size: CGSize, time: Double) {
        let cw = size.width / CGFloat(cols)
        let ch = size.height / CGFloat(rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let x0 = CGFloat(c) * cw, y0 = CGFloat(r) * ch
                let x1 = x0 + cw, y1 = y0 + ch
                // Two triangles per cell, each with its own shifting shade.
                let shadeA = facetShade(r: r, c: c, tri: 0, time: time)
                let shadeB = facetShade(r: r, c: c, tri: 1, time: time)
                fillTriangle(context, CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x0, y: y1), shade: shadeA)
                fillTriangle(context, CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1), shade: shadeB)
            }
        }
    }

    /// Facet shading in roughly [-0.16, 0.16] — positive = white highlight,
    /// negative = dark shadow — driven by the facet's position and time so the
    /// "light" sweeps across the mesh.
    private func facetShade(r: Int, c: Int, tri: Int, time: Double) -> Double {
        0.16 * sin(time * 1.4 + Double(r + c) * 0.7 + Double(tri) * 1.1)
    }

    private func fillTriangle(_ context: GraphicsContext, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, shade: Double) {
        var path = Path()
        path.move(to: p0); path.addLine(to: p1); path.addLine(to: p2); path.closeSubpath()
        let color: Color = shade >= 0 ? .white : .black
        context.fill(path, with: .color(color.opacity(abs(shade))))
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
