import SwiftUI

// MARK: - LiquidAuraArtworkView
//
// Three large, heavily blurred "blobs" sampled from the artwork's palette
// drift and breathe independently behind a crisp foreground cover, giving a
// lava-lamp-like ambient glow distinct from Aura Glow's rotating conic
// gradient.

struct LiquidAuraArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?

    @State private var blob1Offset: CGSize = .zero
    @State private var blob2Offset: CGSize = .zero
    @State private var blob3Offset: CGSize = .zero
    @State private var blob1Scale: CGFloat = 1
    @State private var blob2Scale: CGFloat = 1
    @State private var blob3Scale: CGFloat = 1

    var body: some View {
        ZStack {
            blob(color: palette?.primary ?? AppTheme.dynamicAccent, size: 210, offset: blob1Offset, scale: blob1Scale)
            blob(color: palette?.secondary ?? AppTheme.accentSoft, size: 180, offset: blob2Offset, scale: blob2Scale)
            blob(color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(0.8), size: 150, offset: blob3Offset, scale: blob3Scale)

            artwork(size: 260)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
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

    private func blob(color: Color, size: CGFloat, offset: CGSize, scale: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 55)
            .opacity(isPlaying ? 0.55 : 0.28)
            .scaleEffect(scale)
            .offset(offset)
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
    }

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        if let song {
            ArtworkThumbnail(song: song, size: size)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
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
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                blob1Offset = CGSize(width: 50, height: -34)
                blob1Scale = 1.15
            }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                blob2Offset = CGSize(width: -56, height: 32)
                blob2Scale = 0.9
            }
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                blob3Offset = CGSize(width: 24, height: 54)
                blob3Scale = 1.2
            }
        } else {
            withAnimation(.easeOut(duration: 0.8)) {
                blob1Offset = .zero
                blob2Offset = .zero
                blob3Offset = .zero
                blob1Scale = 1
                blob2Scale = 1
                blob3Scale = 1
            }
        }
    }
}
