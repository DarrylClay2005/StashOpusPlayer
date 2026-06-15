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
    @State private var auraRotation: Double = 0
    @State private var breathe: CGFloat = 1.0
    @State private var palette: ArtworkPalette?

    var body: some View {
        ZStack {
            // Radiating aura — a large, slowly rotating conic gradient built
            // from the artwork's dominant colors, breathing in and out behind
            // everything else. This is what gives Aura Glow a "living,"
            // color-driven feel distinct from Neon Glow's hard-edged rings.
            if let palette {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                palette.primary,
                                palette.secondary,
                                palette.primary.opacity(0.6),
                                palette.secondary,
                                palette.primary,
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 340, height: 340)
                    .blur(radius: 60)
                    .opacity(isPlaying ? 0.55 : 0.3)
                    .scaleEffect(breathe)
                    .rotationEffect(.degrees(auraRotation))
            }

            // Ambient blurred aura — the artwork's own colors, drifting
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
        .onAppear {
            updateAnimations(playing: isPlaying)
        }
        .onChange(of: isPlaying) { playing in updateAnimations(playing: playing) }
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
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                breathe = 1.15
            }
            withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
                auraRotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.8)) {
                pulse = 1.0
                drift = 0
                breathe = 1.0
                auraRotation = 0
            }
        }
    }
}
