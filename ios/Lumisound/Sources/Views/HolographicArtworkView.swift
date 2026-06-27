import SwiftUI

// MARK: - HolographicArtworkView — "Foil Shimmer"
//
// The cover under an iridescent foil: a rotating rainbow angular gradient plus a
// sweeping specular sheen, like holographic trading-card foil catching light.
struct HolographicArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var spin = false
    @State private var sheen: CGFloat = -1

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        StyleCover(song: song, size: 300, cornerRadius: 20)
            .clipShape(shape)
            .overlay(
                AngularGradient(
                    colors: [.pink, .purple, .blue, .cyan, .green, .yellow, .pink],
                    center: .center,
                    angle: .degrees(spin ? 360 : 0)
                )
                .blendMode(.overlay)
                .opacity(isPlaying ? 0.5 : 0.3)
                .clipShape(shape)
            )
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.6), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.size.height * 0.4)
                        .offset(y: sheen * geo.size.height)
                        .blendMode(.plusLighter)
                }
                .clipShape(shape)
            )
            .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .purple.opacity(0.4), radius: 28)
            .frame(width: 300, height: 300)
            .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 3.0))
            .onAppear {
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spin = true }
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { sheen = 1 }
            }
    }
}
