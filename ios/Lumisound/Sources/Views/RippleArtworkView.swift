import SwiftUI

// MARK: - RippleArtworkView
//
// The cover seen under water: concentric rings continuously expand outward from
// the center like raindrops on a pond, drawn over the art and clipped to it,
// while the cover itself gently "breathes." A calm, organic motion unlike any
// of the other styles (which are static, blurred, or linear).

struct RippleArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var breathe: CGFloat = 1

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private let ringCount = 5

    var body: some View {
        artwork(size: 280)
            .scaleEffect(breathe)
            .clipShape(shape)
            .overlay(
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
                    Canvas { context, size in
                        let t = isPlaying ? timeline.date.timeIntervalSinceReferenceDate : 0.4
                        drawRipples(context: context, size: size, time: t)
                    }
                }
                .clipShape(shape)
            )
            .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
            .frame(width: 320, height: 320)
            .onAppear { animate(playing: isPlaying) }
            .onChange(of: isPlaying) { animate(playing: $0) }
            .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
    }

    private func drawRipples(context: GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = max(size.width, size.height) * 0.72
        let tint = palette?.secondary ?? AppTheme.accentSoft
        for k in 0..<ringCount {
            // Each ring's expansion is offset so they emanate in sequence.
            let frac = ((time * 0.35) + Double(k) / Double(ringCount)).truncatingRemainder(dividingBy: 1)
            let radius = CGFloat(frac) * maxR
            let fade = 1.0 - frac                 // brightest near the center, fading out
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(tint.opacity(0.45 * fade)),
                lineWidth: 2.5
            )
        }
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                breathe = 1.03
            }
        } else {
            withAnimation(.easeOut(duration: 0.6)) { breathe = 1 }
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
