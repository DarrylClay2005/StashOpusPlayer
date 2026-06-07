import SwiftUI

// MARK: - MinimalistArtworkView
//
// Ultra-clean square album art with a soft shadow.
// A thin progress bar is overlaid as a line immediately below the art,
// driven by the player's position/duration passed in.

struct MinimalistArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    /// Playback progress in [0, 1]. Pass 0 if unavailable.
    var progress: Double = 0

    @EnvironmentObject private var library: LibraryManager
    @State private var breathe = false
    @State private var shadowPulse = false

    private let artSize: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            // Album art — square, no decorations
            Group {
                if let song {
                    ArtworkThumbnail(song: song, size: artSize)
                        .environmentObject(library)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.surface, AppTheme.elevatedSurface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: artSize, height: artSize)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 80, weight: .semibold))
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(breathe ? 1.022 : 1.0)
            .shadow(
                color: AppTheme.dynamicAccent.opacity(shadowPulse ? 0.45 : 0.18),
                radius: shadowPulse ? 32 : 20,
                x: 0, y: 12
            )
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: shadowPulse)

            // Thin progress line with animated fill
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.surface.opacity(0.6))
                        .frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentSoft, AppTheme.dynamicAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))), height: 3)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
            }
            .frame(width: artSize, height: 3)
            .padding(.top, 10)
        }
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onAppear {
            updateAnimations(playing: isPlaying)
        }
    }

    private func updateAnimations(playing: Bool) {
        breathe = playing
        shadowPulse = playing
    }
}
