import SwiftUI

// MARK: - FloatingCardsArtworkView
//
// Three copies of the cover floating in 3D space: a deep blurred card and a
// mid card tilted back behind a crisp, perspective-tilted front card. The whole
// stack gently wobbles in 3D (rotation3DEffect) and drifts while playing, over
// a soft palette glow — a real sense of depth, not a flat stack.

struct FloatingCardsArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var wobble: CGFloat = 0
    @State private var float: CGFloat = 0

    private let cardSize: CGFloat = 230

    var body: some View {
        ZStack {
            // Palette glow.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette?.primary ?? AppTheme.dynamicAccent)
                .frame(width: cardSize, height: cardSize)
                .blur(radius: 50)
                .opacity(isPlaying ? 0.45 : 0.28)

            // Deep card.
            card(size: cardSize)
                .blur(radius: 5)
                .opacity(0.55)
                .scaleEffect(0.86)
                .rotationEffect(.degrees(-9))
                .offset(x: -34 + wobble * 6, y: 22 - float * 4)

            // Mid card.
            card(size: cardSize)
                .opacity(0.8)
                .scaleEffect(0.93)
                .rotationEffect(.degrees(6))
                .offset(x: 26 - wobble * 5, y: -10 + float * 3)

            // Front crisp card, perspective-tilted.
            card(size: cardSize)
                .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 16)
                .rotation3DEffect(.degrees(Double(wobble) * 6), axis: (x: 1, y: 0, z: 0))
                .rotation3DEffect(.degrees(Double(wobble) * -8), axis: (x: 0, y: 1, z: 0))
                .offset(y: float * 5)
        }
        .frame(width: 320, height: 320)
        .onAppear { animate(playing: isPlaying) }
        .onChange(of: isPlaying) { animate(playing: $0) }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { wobble = 1 }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { float = 1 }
        } else {
            withAnimation(.easeOut(duration: 0.7)) { wobble = 0; float = 0 }
        }
    }

    private func card(size: CGFloat) -> some View {
        artwork(size: size)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.surface, AppTheme.elevatedSurface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.27, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }
}
