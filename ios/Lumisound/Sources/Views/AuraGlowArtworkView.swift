import SwiftUI

// MARK: - AuraGlowArtworkView
//
// Apple Music-style ambient look: a large, heavily blurred copy of the
// artwork glows behind a smaller, crisp copy on top. The blurred aura
// slowly drifts and pulses while playing.

struct AuraGlowArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    @EnvironmentObject private var library: LibraryManager

    @State private var pulse: CGFloat = 1.0
    @State private var drift: CGFloat = 0

    var body: some View {
        ZStack {
            // Ambient blurred aura
            artwork(size: 300)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .blur(radius: 40)
                .opacity(isPlaying ? 0.85 : 0.45)
                .scaleEffect(pulse)
                .offset(x: drift, y: -drift * 0.4)

            // Crisp foreground artwork
            artwork(size: 260)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        }
        .frame(width: 320, height: 320)
        .onAppear { updateAnimations(playing: isPlaying) }
        .onChange(of: isPlaying) { playing in updateAnimations(playing: playing) }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                        .font(.system(size: size * 0.27, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }

    private func updateAnimations(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                pulse = 1.12
            }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = 14
            }
        } else {
            withAnimation(.easeOut(duration: 0.8)) {
                pulse = 1.0
                drift = 0
            }
        }
    }
}
