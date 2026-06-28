import SwiftUI

// MARK: - RetroCRTArtworkView — "Glitch Wave"
//
// The cover with VHS/CRT glitch: RGB channel split, scanlines, and a glitch band
// that scrolls down the image.
struct RetroCRTArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var jitter = false
    @State private var band = false

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        ZStack {
            // RGB-split copies behind the crisp cover.
            StyleCover(song: song, size: 290, cornerRadius: 16)
                .clipShape(shape)
                .colorMultiply(.red)
                .offset(x: jitter ? -3.5 : 3.5)
                .blendMode(.screen)
                .opacity(0.55)
            StyleCover(song: song, size: 290, cornerRadius: 16)
                .clipShape(shape)
                .colorMultiply(.cyan)
                .offset(x: jitter ? 3.5 : -3.5)
                .blendMode(.screen)
                .opacity(0.55)

            StyleCover(song: song, size: 290, cornerRadius: 16)
                .clipShape(shape)

            scanlines.clipShape(shape)

            // Scrolling glitch band.
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 290, height: 26)
                .offset(y: band ? 150 : -150)
                .blendMode(.plusLighter)
                .clipShape(shape)
        }
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        .frame(width: 290, height: 290)
        .shadow(color: .black.opacity(0.5), radius: 22, y: 12)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 4, speed: 3.0))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) { jitter = true }
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) { band = true }
        }
    }

    private var scanlines: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.3)))
                y += 3
            }
        }
    }
}
