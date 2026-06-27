import SwiftUI

// MARK: - PopArtArtworkView — "Comic Halftone"
//
// The cover as a comic panel: a halftone dot screen over the art, a bold frame,
// and a slow hue-cycling colour wash.
struct PopArtArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var hue: Double = 0

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        StyleCover(song: song, size: 300, cornerRadius: 14)
            .clipShape(shape)
            .overlay(halftone.blendMode(.multiply).opacity(0.22).clipShape(shape))
            .overlay(
                LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blendMode(.color)
                    .opacity(isPlaying ? 0.3 : 0.18)
                    .hueRotation(.degrees(hue))
                    .clipShape(shape)
            )
            .overlay(shape.stroke(.white, lineWidth: 5))
            .overlay(shape.stroke(.black.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
            .frame(width: 300, height: 300)
            .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 2.8))
            .onAppear {
                withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { hue = 360 }
            }
    }

    private var halftone: some View {
        Canvas { ctx, size in
            let step: CGFloat = 11
            let r: CGFloat = 2.1
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                             with: .color(.black))
                    x += step
                }
                y += step
            }
        }
    }
}
