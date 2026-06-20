import SwiftUI

// MARK: - PopArtArtworkView
//
// A Lichtenstein-style comic / pop-art treatment: the cover sits on a bold
// Ben-Day-dot backdrop (radiating halftone) inside a thick black comic frame,
// with a printed halftone-dot overlay on the art itself. Graphic and high-
// contrast — nothing else in the set has this print aesthetic.

struct PopArtArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var burst: CGFloat = 1

    var body: some View {
        ZStack {
            // Ben-Day dot backdrop on a flat pop color.
            let bg = palette?.secondary ?? AppTheme.accentSoft
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(bg.opacity(0.9))
                .frame(width: 320, height: 320)
                .overlay(
                    Canvas { context, size in
                        drawHalftone(context: context, size: size, spacing: 16, radius: 3.0,
                                     color: .black.opacity(0.18))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                )

            // Radiating "burst" rays behind the cover (comic action lines).
            Canvas { context, size in
                drawRays(context: context, size: size)
            }
            .frame(width: 300, height: 300)
            .scaleEffect(burst)
            .opacity(0.18)

            // Cover with its own printed halftone overlay + bold comic frame.
            artwork(size: 222)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    Canvas { context, size in
                        drawHalftone(context: context, size: size, spacing: 9, radius: 1.4,
                                     color: .black.opacity(0.16))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.black, lineWidth: 5)
                )
                .shadow(color: .black.opacity(0.4), radius: 0, x: 6, y: 6)  // hard comic shadow
        }
        .frame(width: 320, height: 320)
        .onAppear { animate(playing: isPlaying) }
        .onChange(of: isPlaying) { animate(playing: $0) }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func drawHalftone(context: GraphicsContext, size: CGSize, spacing: CGFloat, radius: CGFloat, color: Color) {
        var y: CGFloat = spacing / 2
        var row = 0
        while y < size.height {
            // Offset alternate rows for a classic halftone lattice.
            let xStart = (row % 2 == 0) ? spacing / 2 : spacing
            var x = xStart
            while x < size.width {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color)
                )
                x += spacing
            }
            y += spacing
            row += 1
        }
    }

    private func drawRays(context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = 24
        for i in 0..<count where i % 2 == 0 {
            let a0 = Double(i) / Double(count) * 2 * Double.pi
            let a1 = Double(i + 1) / Double(count) * 2 * Double.pi
            var path = Path()
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + CGFloat(cos(a0)) * size.width, y: center.y + CGFloat(sin(a0)) * size.height))
            path.addLine(to: CGPoint(x: center.x + CGFloat(cos(a1)) * size.width, y: center.y + CGFloat(sin(a1)) * size.height))
            path.closeSubpath()
            context.fill(path, with: .color(.black))
        }
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { burst = 1.12 }
        } else {
            withAnimation(.easeOut(duration: 0.6)) { burst = 1 }
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
