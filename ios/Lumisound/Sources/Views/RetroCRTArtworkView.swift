import SwiftUI

// MARK: - RetroCRTArtworkView — "Glitch Wave"
//
// The cover with heavy VHS/CRT glitch: strong RGB channel split, hard scanlines,
// a bright scrolling glitch band, and a displaced slice.
struct RetroCRTArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var jitter = false
    @State private var band = false

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        ZStack {
            StyleCover(song: song, size: 296, cornerRadius: 16)
                .clipShape(shape)
                .colorMultiply(.red)
                .offset(x: jitter ? -7 : 7)
                .blendMode(.screen)
                .opacity(0.7)
            StyleCover(song: song, size: 296, cornerRadius: 16)
                .clipShape(shape)
                .colorMultiply(.cyan)
                .offset(x: jitter ? 7 : -7)
                .blendMode(.screen)
                .opacity(0.7)

            StyleCover(song: song, size: 296, cornerRadius: 16)
                .clipShape(shape)

            // Displaced slice — a horizontal band of the cover shoved sideways.
            StyleCover(song: song, size: 296, cornerRadius: 0)
                .frame(width: 296, height: 30)
                .clipped()
                .offset(x: band ? 16 : -16, y: -40)
                .opacity(0.9)
                .clipShape(shape)

            scanlines.clipShape(shape)

            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.4), .cyan.opacity(0.3), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 296, height: 34)
                .offset(y: band ? 150 : -150)
                .blendMode(.plusLighter)
                .clipShape(shape)
        }
        .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
        .frame(width: 296, height: 296)
        .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 4, speed: 3.0))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true)) { jitter = true }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { band = true }
        }
    }

    private var scanlines: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1.4)), with: .color(.black.opacity(0.42)))
                y += 3
            }
        }
    }
}
