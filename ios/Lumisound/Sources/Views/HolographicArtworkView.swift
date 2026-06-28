import SwiftUI

// MARK: - HolographicArtworkView — "Foil Shimmer"
//
// The cover under bright holographic foil: a rotating saturated rainbow wash, a
// wide moving specular sheen, and scattered twinkling sparkles.
struct HolographicArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var spin = false
    @State private var sheen: CGFloat = -1.2
    @State private var twinkle = false

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    private let sparkles: [(x: CGFloat, y: CGFloat, s: CGFloat)] = (0..<7).map { i in
        (CGFloat((i &* 89) % 250) + 25, CGFloat((i &* 137) % 250) + 25, CGFloat(5 + (i % 3) * 3))
    }

    var body: some View {
        StyleCover(song: song, size: 300, cornerRadius: 20)
            .clipShape(shape)
            .overlay(
                AngularGradient(
                    colors: [.pink, .purple, .blue, .cyan, .green, .yellow, .pink],
                    center: .center,
                    angle: .degrees(spin ? 360 : 0)
                )
                .blendMode(.colorDodge)
                .opacity(isPlaying ? 0.55 : 0.38)
                .clipShape(shape)
            )
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: geo.size.width * 0.55)
                        .rotationEffect(.degrees(24))
                        .offset(x: sheen * geo.size.width)
                        .blendMode(.plusLighter)
                }
                .clipShape(shape)
            )
            .overlay(
                ZStack {
                    ForEach(Array(sparkles.enumerated()), id: \.offset) { _, sp in
                        Image(systemName: "sparkle")
                            .font(.system(size: sp.s + 6))
                            .foregroundStyle(.white)
                            .shadow(color: .white, radius: 4)
                            .position(x: sp.x, y: sp.y)
                            .opacity(twinkle ? 0.95 : 0.2)
                    }
                }
                .frame(width: 300, height: 300)
                .clipShape(shape)
            )
            .overlay(shape.stroke(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .purple.opacity(0.45), radius: 28)
            .shadow(color: .cyan.opacity(0.3), radius: 18)
            .frame(width: 300, height: 300)
            .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 3.0))
            .onAppear {
                withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { spin = true }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { sheen = 1.2 }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { twinkle = true }
            }
    }
}
