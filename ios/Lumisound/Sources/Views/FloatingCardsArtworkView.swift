import SwiftUI

struct FloatingCardsArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    private let cardSize: CGFloat = 240

    @State private var frontFloat    = false
    @State private var backFloat     = false
    @State private var frontRock     = false
    @State private var backRock      = false
    @State private var deepFloat     = false
    @State private var drift: CGFloat = 0
    @State private var palette: ArtworkPalette?

    var body: some View {
        ZStack {
            // Ambient glow — a soft blurred wash sampled from the artwork's
            // dominant colors, giving the whole stack a sense of depth and
            // tying the floating cards to the track's palette.
            if let palette {
                Circle()
                    .fill(palette.primary)
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .opacity(0.5)
                    .offset(x: -30 + drift, y: -10 - drift * 0.4)

                Circle()
                    .fill(palette.secondary)
                    .frame(width: 220, height: 220)
                    .blur(radius: 60)
                    .opacity(0.4)
                    .offset(x: 40 - drift, y: 30 + drift * 0.3)
            }

            // Deep card — partially visible, heavy tilt, far behind, most blurred
            cardView(song: song, size: cardSize * 0.88, cornerRadius: 12)
                .rotationEffect(.degrees(backRock ? 15 : 11))
                .offset(x: 30 + drift * 0.5, y: deepFloat ? 4 : 12)
                .opacity(0.5)
                .blur(radius: 3)
                .scaleEffect(0.96)
                .zIndex(0)

            // Back card — current artwork, rotated, offset, gently blurred
            // for parallax depth relative to the crisp front card
            cardView(song: song, size: cardSize, cornerRadius: 14)
                .rotationEffect(.degrees(backRock ? 10 : 6))
                .offset(x: 18 + drift * 0.25, y: backFloat ? -7 : 5)
                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
                .blur(radius: 1.2)
                .opacity(0.85)
                .zIndex(1)

            // Front card — main focus, subtle tilt, slightly left, fully crisp
            cardView(song: song, size: cardSize, cornerRadius: 14)
                .rotationEffect(.degrees(frontRock ? -2 : -6))
                .offset(x: -8, y: frontFloat ? -10 : 4)
                .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 12)
                .zIndex(2)
        }
        .frame(width: cardSize + 80, height: cardSize + 60)
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onAppear {
            updateAnimations(playing: isPlaying)
        }
        .task(id: song?.id) {
            await loadPalette()
        }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    private func loadPalette() async {
        guard let song else {
            palette = nil
            return
        }
        var image = library.artwork(for: song)
        if image == nil {
            image = await ArtworkService.shared.loadArtwork(for: song)
        }
        guard let image else {
            palette = nil
            return
        }
        palette = ArtworkColorExtractor.palette(from: image)
    }

    @ViewBuilder
    private func cardView(song: Song?, size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: AppTheme.dynamicAccent.opacity(0.2), radius: 10, x: 0, y: 4)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.surface, AppTheme.elevatedSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        }
    }

    private func updateAnimations(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                frontFloat = true
                frontRock  = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.4)) {
                backFloat = true
                backRock  = true
            }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true).delay(0.8)) {
                deepFloat = true
            }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                drift = 18
            }
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                frontFloat = false
                frontRock  = false
                backFloat  = false
                backRock   = false
                deepFloat  = false
                drift      = 0
            }
        }
    }
}
