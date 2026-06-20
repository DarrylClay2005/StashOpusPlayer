import SwiftUI

// MARK: - HaloRingArtworkView
//
// Circular cover art encircled by a palette-colored "halo" — a soft glowing
// ring that slowly rotates and breathes while playing, with a thin crisp
// accent ring on top. A modern, minimal, radial take on cover display.

struct HaloRingArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var rotation: Double = 0
    @State private var breathe: CGFloat = 1

    var body: some View {
        ZStack {
            // Soft glowing halo behind.
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            palette?.primary ?? AppTheme.dynamicAccent,
                            palette?.secondary ?? AppTheme.accentSoft,
                            palette?.primary ?? AppTheme.dynamicAccent,
                        ],
                        center: .center
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 34)
                .opacity(isPlaying ? 0.55 : 0.3)
                .scaleEffect(breathe)
                .rotationEffect(.degrees(rotation))

            // Crisp thin accent ring.
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            (palette?.primary ?? AppTheme.dynamicAccent),
                            (palette?.secondary ?? AppTheme.accentSoft),
                            (palette?.primary ?? AppTheme.dynamicAccent),
                        ],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 268, height: 268)
                .rotationEffect(.degrees(-rotation))

            // Circular cover.
            artwork(size: 240)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
        }
        .frame(width: 320, height: 320)
        .onAppear { animate(playing: isPlaying) }
        .onChange(of: isPlaying) { animate(playing: $0) }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func animate(playing: Bool) {
        if playing {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                breathe = 1.08
            }
        } else {
            withAnimation(.easeOut(duration: 0.6)) { breathe = 1 }
        }
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            Circle()
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
