import SwiftUI

// MARK: - FloatingCardsArtworkView
//
// Two overlapping album art cards at different rotation angles.
// The "back" card is slightly larger and rotated more. Both float
// with independent animation phases. If there is no previous song
// art available, the same artwork is shown at a different tint/tilt.

struct FloatingCardsArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager

    private let cardSize: CGFloat = 240

    @State private var frontFloat  = false
    @State private var backFloat   = false

    var body: some View {
        ZStack {
            // Back card — current artwork, more tilt, slightly offset
            cardView(song: song, size: cardSize, cornerRadius: 14)
                .rotationEffect(.degrees(8))
                .offset(x: 18, y: backFloat ? -6 : 6)
                .zIndex(0)

            // Front card — same artwork, straighter, main focus
            cardView(song: song, size: cardSize, cornerRadius: 14)
                .rotationEffect(.degrees(-4))
                .offset(x: -6, y: frontFloat ? -8 : 4)
                .shadow(color: .black.opacity(0.50), radius: 20, x: 0, y: 10)
                .zIndex(1)
        }
        .frame(width: cardSize + 60, height: cardSize + 40)
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onAppear {
            updateAnimations(playing: isPlaying)
        }
    }

    @ViewBuilder
    private func cardView(song: Song?, size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: AppTheme.accent.opacity(0.25), radius: 12, x: 0, y: 6)
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
                        .foregroundStyle(AppTheme.accent)
                }
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        }
    }

    private func updateAnimations(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                frontFloat = true
            }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true).delay(0.4)) {
                backFloat = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                frontFloat = false
                backFloat  = false
            }
        }
    }
}
