import SwiftUI

// MARK: - GlassmorphismArtworkView — "Frost Panels"
//
// A frosted glass card over a heavily-blurred version of the art, with bold
// floating glass shards (white-edged, sheen-topped) drifting in front.
struct GlassmorphismArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var float = false

    private let card = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        ZStack {
            StyleCover(song: song, size: 330, cornerRadius: 28)
                .blur(radius: 44)
                .opacity(0.9)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.black.opacity(0.18))

            shard(w: 120, h: 165, x: float ? -104 : -90, y: -52, rot: -12)
            shard(w: 96, h: 128, x: float ? 112 : 98, y: 82, rot: 14)
            shard(w: 78, h: 98, x: 78, y: float ? -118 : -104, rot: 8)

            StyleCover(song: song, size: 228, cornerRadius: 22)
                .clipShape(card)
                .overlay(
                    card.stroke(
                        LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
                )
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)
                        .clipShape(card)
                        .allowsHitTesting(false)
                )
                .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
        }
        .frame(width: 330, height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.2))
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { float = true }
        }
    }

    private func shard(w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, rot: Double) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.55), lineWidth: 1.5))
            .frame(width: w, height: h)
            .rotationEffect(.degrees(rot))
            .offset(x: x, y: y)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
    }
}
