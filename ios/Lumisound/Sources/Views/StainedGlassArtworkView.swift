import SwiftUI

// MARK: - StainedGlassArtworkView — "Prism Glass"
//
// The cover seen through leaded stained glass: a slowly-rotating prismatic light
// wash over the art, divided by dark leading lines.
struct StainedGlassArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var spin = false

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    private var tint: Color { palette?.primary ?? AppTheme.dynamicAccent }

    var body: some View {
        StyleCover(song: song, size: 300, cornerRadius: 18)
            .clipShape(shape)
            .overlay(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    center: .center,
                    angle: .degrees(spin ? 360 : 0)
                )
                .blendMode(.overlay)
                .opacity(isPlaying ? 0.55 : 0.35)
                .clipShape(shape)
            )
            .overlay(leading.clipShape(shape))
            .overlay(shape.stroke(.black.opacity(0.5), lineWidth: 4))
            .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
            .frame(width: 300, height: 300)
            .shadow(color: tint.opacity(0.45), radius: 26)
            .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.0))
            .onAppear {
                withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
            }
            .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
            .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private var leading: some View {
        Canvas { ctx, size in
            var path = Path()
            let sx = size.width / 4
            let sy = size.height / 4
            var x = sx
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += sx }
            var y = sy
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += sy }
            path.move(to: .zero); path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.move(to: CGPoint(x: size.width, y: 0)); path.addLine(to: CGPoint(x: 0, y: size.height))
            ctx.stroke(path, with: .color(.black.opacity(0.4)), lineWidth: 2.5)
        }
    }
}
