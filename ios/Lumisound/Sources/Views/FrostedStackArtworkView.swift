import SwiftUI

// MARK: - FrostedStackArtworkView
//
// Three progressively-smaller frosted-glass copies of the artwork fan out
// behind a crisp foreground cover, like a deck of translucent cards. The
// backing cards gently spread apart while playing and collapse back together
// when paused.

struct FrostedStackArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var spread: CGFloat = 0

    var body: some View {
        ZStack {
            // Two frosted backing cards.
            frostedCard(size: 250, rotation: -6, offset: CGSize(width: -spread, height: spread * 0.4), opacity: 0.5)
            frostedCard(size: 250, rotation: 6, offset: CGSize(width: spread, height: spread * 0.4), opacity: 0.65)

            // Crisp foreground cover.
            artwork(size: 250)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 22, x: 0, y: 14)
        }
        .frame(width: 320, height: 320)
        .onAppear { animate(playing: isPlaying) }
        .onChange(of: isPlaying) { animate(playing: $0) }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func frostedCard(size: CGFloat, rotation: Double, offset: CGSize, opacity: Double) -> some View {
        artwork(size: size)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill((palette?.primary ?? AppTheme.dynamicAccent).opacity(0.10))
            )
            .blur(radius: 6)
            .opacity(opacity)
            .rotationEffect(.degrees(rotation))
            .offset(offset)
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                spread = 34
            }
        } else {
            withAnimation(.easeOut(duration: 0.7)) { spread = 12 }
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
