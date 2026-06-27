import SwiftUI

// MARK: - GlassmorphismArtworkView — "Frost Panels"
//
// The cover behind a frosted glass card, with smaller translucent glass panels
// drifting in front of a heavily-blurred version of the same art.
struct GlassmorphismArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var float = false

    var body: some View {
        ZStack {
            StyleCover(song: song, size: 330, cornerRadius: 26)
                .blur(radius: 38)
                .opacity(0.7)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 90, height: 120)
                .rotationEffect(.degrees(-12))
                .offset(x: float ? -112 : -96, y: float ? -72 : -52)
                .opacity(0.5)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 70, height: 92)
                .rotationEffect(.degrees(14))
                .offset(x: float ? 112 : 96, y: float ? 82 : 62)
                .opacity(0.45)

            StyleCover(song: song, size: 250, cornerRadius: 22)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        }
        .frame(width: 330, height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.2))
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { float = true }
        }
    }
}
