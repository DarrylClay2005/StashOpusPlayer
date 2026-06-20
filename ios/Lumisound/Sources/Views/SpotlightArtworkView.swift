import SwiftUI

// MARK: - SpotlightArtworkView
//
// A dramatic "on stage" treatment: the cover sits in a dark vignette with a
// soft palette-tinted spotlight cone sweeping gently from above while playing.
// Gives a moody, gallery-lit presentation distinct from the flat Album Art
// style.

struct SpotlightArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var sweep: CGFloat = -1

    var body: some View {
        ZStack {
            // Dark stage backdrop with vignette.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.05), Color.black.opacity(0.55)],
                        center: .center, startRadius: 40, endRadius: 230
                    )
                )
                .frame(width: 320, height: 320)

            // Spotlight cone — a soft palette-tinted beam from top, sweeping.
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            (palette?.primary ?? AppTheme.dynamicAccent).opacity(isPlaying ? 0.45 : 0.2),
                            .clear,
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 200, height: 300)
                .blur(radius: 30)
                .rotationEffect(.degrees(Double(sweep) * 10))
                .offset(y: -40)

            // Crisp lit cover.
            artwork(size: 240)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.4), radius: 30, x: 0, y: 0)
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 18)
        }
        .frame(width: 320, height: 320)
        .onAppear { animate(playing: isPlaying) }
        .onChange(of: isPlaying) { animate(playing: $0) }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                sweep = 1
            }
        } else {
            withAnimation(.easeOut(duration: 0.7)) { sweep = 0 }
        }
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
