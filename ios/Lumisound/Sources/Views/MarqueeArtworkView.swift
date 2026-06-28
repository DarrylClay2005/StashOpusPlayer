import SwiftUI

// MARK: - MarqueeArtworkView — "Marquee Bulbs"
//
// The cover framed by a ring of theater-marquee bulbs that chase and twinkle.
struct MarqueeArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var chase = false

    private let count = 28
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(white: 0.06))

            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(.yellow)
                    .frame(width: 9, height: 9)
                    .shadow(color: .yellow.opacity(0.9), radius: chase ? 6 : 2)
                    .opacity(chase ? 1.0 : 0.35)
                    .offset(y: -140)
                    .rotationEffect(.degrees(Double(i) / Double(count) * 360))
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(Double(i) * 0.05), value: chase)
            }

            StyleCover(song: song, size: 220, cornerRadius: 14)
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 18)
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.0))
        .onAppear { chase = true }
    }
}
