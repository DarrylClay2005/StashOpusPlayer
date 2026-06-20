import SwiftUI

// MARK: - WaveBorderArtworkView
//
// The cover art framed by a live, reactive equalizer border: palette-colored
// bars ring all four edges and animate (a travelling sine wave) while playing,
// settling flat when paused. A modern "the art is reacting to the music"
// presentation.

struct WaveBorderArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var phase: Double = 0

    private let barsPerSide = 18

    var body: some View {
        ZStack {
            // Glow behind, palette-tinted.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(palette?.primary ?? AppTheme.dynamicAccent)
                .frame(width: 300, height: 300)
                .blur(radius: 40)
                .opacity(isPlaying ? 0.4 : 0.2)

            // Reactive bar frame.
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    drawBars(context: context, size: size, time: isPlaying ? t : 0)
                }
                .frame(width: 296, height: 296)
            }

            // Crisp cover.
            artwork(size: 244)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 10)
        }
        .frame(width: 320, height: 320)
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    /// Draws palette-colored bars along the four edges of `size`, their lengths
    /// modulated by a travelling sine wave so the whole frame appears to pulse.
    private func drawBars(context: GraphicsContext, size: CGSize, time: Double) {
        let primary = palette?.primary ?? AppTheme.dynamicAccent
        let secondary = palette?.secondary ?? AppTheme.accentSoft
        let maxLen: CGFloat = 14
        let barW: CGFloat = 3

        func barHeight(_ i: Int, _ offset: Double) -> CGFloat {
            let wave = 0.45 + 0.55 * (0.5 + 0.5 * sin(time * 4 + Double(i) * 0.5 + offset))
            return maxLen * CGFloat(time == 0 ? 0.35 : wave)
        }

        // Top + bottom edges.
        for i in 0..<barsPerSide {
            let x = size.width * (CGFloat(i) + 0.5) / CGFloat(barsPerSide)
            let hTop = barHeight(i, 0)
            context.fill(
                Path(roundedRect: CGRect(x: x - barW / 2, y: 0, width: barW, height: hTop), cornerRadius: barW / 2),
                with: .color(primary)
            )
            let hBot = barHeight(i, .pi)
            context.fill(
                Path(roundedRect: CGRect(x: x - barW / 2, y: size.height - hBot, width: barW, height: hBot), cornerRadius: barW / 2),
                with: .color(secondary)
            )
        }
        // Left + right edges.
        for i in 0..<barsPerSide {
            let y = size.height * (CGFloat(i) + 0.5) / CGFloat(barsPerSide)
            let hLeft = barHeight(i, .pi / 2)
            context.fill(
                Path(roundedRect: CGRect(x: 0, y: y - barW / 2, width: hLeft, height: barW), cornerRadius: barW / 2),
                with: .color(secondary)
            )
            let hRight = barHeight(i, 3 * .pi / 2)
            context.fill(
                Path(roundedRect: CGRect(x: size.width - hRight, y: y - barW / 2, width: hRight, height: barW), cornerRadius: barW / 2),
                with: .color(primary)
            )
        }
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
