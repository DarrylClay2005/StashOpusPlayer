import SwiftUI

// MARK: - MarqueeArtworkView
//
// A cinema-marquee treatment: the cover sits on a dark theater panel ringed by
// incandescent bulbs that "chase" around the border (a bright spot travels the
// perimeter while playing, all bulbs idle-glow when paused). Nothing else in
// the style set uses a perimeter bulb-chase, so it reads as its own thing.

struct MarqueeArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?

    private let bulbCount = 44
    private let inset: CGFloat = 12

    var body: some View {
        ZStack {
            // Dark theater panel behind everything.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.10, green: 0.09, blue: 0.12))
                .frame(width: 320, height: 320)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

            // Chasing bulbs around the perimeter.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                Canvas { context, size in
                    let t = isPlaying ? timeline.date.timeIntervalSinceReferenceDate : 0
                    drawBulbs(context: context, size: size, time: t)
                }
                .frame(width: 320, height: 320)
            }

            // Cover in the center.
            artwork(size: 232)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.black.opacity(0.6), lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 6)
        }
        .frame(width: 320, height: 320)
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func drawBulbs(context: GraphicsContext, size: CGSize, time: Double) {
        let side = min(size.width, size.height)
        let warm = Color(red: 1.0, green: 0.86, blue: 0.55)
        let accent = palette?.primary ?? AppTheme.dynamicAccent
        for i in 0..<bulbCount {
            let frac = CGFloat(i) / CGFloat(bulbCount)
            let p = pointOnSquare(frac: frac, side: side, inset: inset)
            // Traveling bright spot: phase advances with time, lights a moving cluster.
            let phase = time * 1.8
            let wave = 0.5 + 0.5 * cos(phase - Double(i) * (2 * Double.pi / Double(bulbCount)) * 3)
            let brightness = time == 0 ? 0.45 : wave
            let lit = i % 2 == 0 ? warm : accent
            // Glow halo.
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)),
                with: .color(lit.opacity(0.25 * brightness))
            )
            // Bulb.
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)),
                with: .color(lit.opacity(0.35 + 0.65 * brightness))
            )
        }
    }

    /// Maps a 0–1 fraction to a point traveling clockwise around the square's
    /// inset perimeter (top → right → bottom → left).
    private func pointOnSquare(frac: CGFloat, side: CGFloat, inset: CGFloat) -> CGPoint {
        let lo = inset
        let hi = side - inset
        let span = hi - lo
        let d = frac.truncatingRemainder(dividingBy: 1) * (span * 4)
        if d < span { return CGPoint(x: lo + d, y: lo) }                 // top
        if d < span * 2 { return CGPoint(x: hi, y: lo + (d - span)) }    // right
        if d < span * 3 { return CGPoint(x: hi - (d - span * 2), y: hi) }// bottom
        return CGPoint(x: lo, y: hi - (d - span * 3))                    // left
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
