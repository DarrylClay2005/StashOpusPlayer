import SwiftUI

/// A soft, animated color wash sampled from the current track's artwork —
/// two large blurred blobs that slowly drift and breathe behind the Now
/// Playing artwork display, similar to Apple Music / Spotify's ambient
/// now-playing backgrounds. Shared across all `NowPlayingArtworkStyle`
/// presets so every style gets a less "flat" backdrop for free.
struct AmbientArtworkBackground: View {
    let song: Song?

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var drift: CGFloat = 0
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            if let palette {
                Circle()
                    .fill(palette.primary)
                    .frame(width: 320, height: 320)
                    .blur(radius: 80)
                    .offset(x: -90 + drift, y: -60 - drift * 0.6)
                    .scaleEffect(pulse)

                Circle()
                    .fill(palette.secondary)
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: 100 - drift, y: 70 + drift * 0.5)
                    .scaleEffect(2 - pulse)
            }
        }
        .opacity(0.55)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.2), value: palette)
        .task(id: song?.id) {
            await loadPalette()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift = 36
            }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                pulse = 1.18
            }
        }
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song)
    }
}
