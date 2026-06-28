import SwiftUI

// MARK: - FloatingCardsArtworkView — "Card Fan"
//
// The cover as the front of a gently breathing fanned stack of cards.
struct FloatingCardsArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var fan = false

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                let depth = Double(3 - i)            // 3 (back) … 1 (near front)
                StyleCover(song: song, size: 250, cornerRadius: 18)
                    .clipShape(shape)
                    .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
                    .scaleEffect(0.9 - CGFloat(i) * 0.015)
                    .rotationEffect(.degrees((i % 2 == 0 ? -1 : 1) * depth * (fan ? 9 : 5)))
                    .offset(y: CGFloat(i) * 8)
                    .opacity(0.45)
                    .blur(radius: 1.5)
            }

            StyleCover(song: song, size: 260, cornerRadius: 18)
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
        }
        .frame(width: 330, height: 330)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 6, speed: 3.0))
        .onAppear {
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) { fan = true }
        }
    }
}
