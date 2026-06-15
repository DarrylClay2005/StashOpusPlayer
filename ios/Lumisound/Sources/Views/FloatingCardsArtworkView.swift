import SwiftUI

// MARK: - FloatingCardsArtworkView
//
// A fanned stack of glass-bordered cards: a crisp front card, a softly
// blurred back card peeking out behind it, and a deep card further back —
// each gently bobbing at its own pace. A diagonal shimmer sweeps across the
// front card while playing, and the whole stack sits over a soft palette-
// driven glow.

struct FloatingCardsArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    private let cardSize: CGFloat = 240

    @State private var frontFloat    = false
    @State private var backFloat     = false
    @State private var deepFloat     = false
    @State private var drift: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -260
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
                    .opacity(0.45)
                    .offset(x: -30 + drift, y: -10 - drift * 0.4)

                Circle()
                    .fill(palette.secondary)
                    .frame(width: 220, height: 220)
                    .blur(radius: 60)
                    .opacity(0.35)
                    .offset(x: 40 - drift, y: 30 + drift * 0.3)
            }

            // Deep card — partially visible, heavy tilt, far behind, most blurred
            cardView(song: song, size: cardSize * 0.86, cornerRadius: 16)
                .rotationEffect(.degrees(13))
                .offset(x: 34 + drift * 0.5, y: deepFloat ? 6 : 14)
                .opacity(0.45)
                .blur(radius: 4)
                .zIndex(0)

            // Back card — current artwork, rotated, offset, gently blurred
            // for parallax depth relative to the crisp front card
            cardView(song: song, size: cardSize, cornerRadius: 18)
                .rotationEffect(.degrees(8))
                .offset(x: 20 + drift * 0.25, y: backFloat ? -6 : 6)
                .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 6)
                .blur(radius: 1.5)
                .opacity(0.8)
                .zIndex(1)

            // Front card — main focus, subtle tilt, slightly left, fully crisp
            cardView(song: song, size: cardSize, cornerRadius: 18)
                .rotationEffect(.degrees(-5))
                .offset(x: -10, y: frontFloat ? -10 : 4)
                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
                .overlay(shimmer.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
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

    /// A diagonal highlight sweep across the front card, like light catching glass.
    private var shimmer: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.16), location: 0.45),
                .init(color: .white.opacity(0.28), location: 0.5),
                .init(color: .white.opacity(0.16), location: 0.55),
                .init(color: .clear, location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: cardSize * 1.4)
        .offset(x: shimmerOffset)
        .allowsHitTesting(false)
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
    }

    @ViewBuilder
    private func cardView(song: Song?, size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let song {
                ArtworkThumbnail(song: song, size: size)
                    .environmentObject(library)
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
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func updateAnimations(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                frontFloat = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.4)) {
                backFloat = true
            }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true).delay(0.8)) {
                deepFloat = true
            }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                drift = 18
            }
            startShimmer()
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                frontFloat = false
                backFloat  = false
                deepFloat  = false
                drift      = 0
            }
            withAnimation(.easeOut(duration: 0.3)) {
                shimmerOffset = -260
            }
        }
    }

    private func startShimmer() {
        shimmerOffset = -260
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
            shimmerOffset = 300
        }
    }
}
