import SwiftUI

// MARK: - StarfieldArtworkView
//
// The cover floats in deep space while a star-warp field streaks outward from
// behind it (stars accelerate from the center to the edges, leaving light
// trails) — a sci-fi "jump to lightspeed" motion when playing, drifting gently
// when paused. The only style with a true 3D-warp particle field.

struct StarfieldArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?

    // Deterministic per-star angle/phase/speed so the field is stable frame-to-frame.
    private let seeds: [(angle: Double, phase: Double, speed: Double)] = {
        var rng = SeededRandom(seed: 0xC0FFEE)
        return (0..<90).map { _ in
            (angle: rng.nextDouble() * 2 * Double.pi,
             phase: rng.nextDouble(),
             speed: 0.25 + rng.nextDouble() * 0.55)
        }
    }()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.05, green: 0.06, blue: 0.12), .black],
                        center: .center, startRadius: 20, endRadius: 230
                    )
                )
                .frame(width: 320, height: 320)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    drawStars(context: context, size: size, time: t, warping: isPlaying)
                }
                .frame(width: 320, height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }

            // Cover floating in the center with a palette glow.
            artwork(size: 200)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.6), radius: 26, x: 0, y: 0)
                .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.5))
        }
        .frame(width: 320, height: 320)
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func drawStars(context: GraphicsContext, size: CGSize, time: Double, warping: Bool) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = max(size.width, size.height) * 0.72
        let starColor = palette?.secondary ?? Color.white
        for s in seeds {
            // Distance from center cycles 0→1; warping speeds it up + adds trails.
            let rate = warping ? s.speed : s.speed * 0.18
            let frac = (time * rate + s.phase).truncatingRemainder(dividingBy: 1)
            let r = CGFloat(frac) * maxR
            let dx = cos(s.angle), dy = sin(s.angle)
            let p = CGPoint(x: center.x + CGFloat(dx) * r, y: center.y + CGFloat(dy) * r)
            let dotSize: CGFloat = 0.6 + CGFloat(frac) * 2.2
            let alpha = min(1.0, frac * 1.4)

            if warping && frac > 0.15 {
                // Light trail: a short streak behind the star toward center.
                let trail = CGFloat(min(28, frac * 40))
                var path = Path()
                path.move(to: CGPoint(x: p.x - CGFloat(dx) * trail, y: p.y - CGFloat(dy) * trail))
                path.addLine(to: p)
                context.stroke(path, with: .color(starColor.opacity(0.5 * alpha)), lineWidth: dotSize)
            }
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - dotSize / 2, y: p.y - dotSize / 2, width: dotSize, height: dotSize)),
                with: .color(starColor.opacity(alpha))
            )
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
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
