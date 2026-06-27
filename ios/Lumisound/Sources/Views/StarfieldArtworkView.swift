import SwiftUI

// MARK: - StarfieldArtworkView — "Cosmos"
//
// The cover sits inside a slowly-rotating field of twinkling stars.
struct StarfieldArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var rotate = false
    @State private var twinkle = false

    // Deterministic star positions within a 320×320 field.
    private let stars: [(x: CGFloat, y: CGFloat, s: CGFloat)] = (0..<70).map { i in
        let x = CGFloat((i &* 73) % 300) + 10
        let y = CGFloat((i &* 151) % 300) + 10
        let s = CGFloat(1 + (i % 3))
        return (x, y, s)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black)

            ZStack {
                ForEach(Array(stars.enumerated()), id: \.offset) { _, st in
                    Circle()
                        .fill(.white)
                        .frame(width: st.s, height: st.s)
                        .position(x: st.x, y: st.y)
                }
            }
            .frame(width: 320, height: 320)
            .rotationEffect(.degrees(rotate ? 360 : 0))
            .opacity(twinkle ? 0.95 : 0.5)

            StyleCover(song: song, size: 240, cornerRadius: 18)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.7), radius: 30)
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.4))
        .onAppear {
            withAnimation(.linear(duration: 70).repeatForever(autoreverses: false)) { rotate = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { twinkle = true }
        }
    }
}
