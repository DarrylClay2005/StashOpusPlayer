import SwiftUI

// MARK: - EditorialArtworkView
//
// A magazine-spread layout: a small, slightly desaturated cover sits beside
// a large serif title with a thin accent rule above it and an uppercase,
// letter-spaced artist line below. A hairline progress rule runs the full
// width beneath, driven by the player's position/duration.

struct EditorialArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    /// Playback progress in [0, 1]. Pass 0 if unavailable.
    var progress: Double = 0

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var breathe = false

    private let artSize: CGFloat = 150
    private let totalWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                artworkContent
                    .frame(width: artSize, height: artSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .saturation(0.85)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((palette?.primary ?? AppTheme.dynamicAccent).opacity(isPlaying ? 0.10 : 0))
                            .blendMode(.overlay)
                    )
                    .scaleEffect(breathe ? 1.015 : 1.0)
                    .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Rectangle()
                        .fill(palette?.primary ?? AppTheme.dynamicAccent)
                        .frame(width: 28, height: 3)

                    Text(song?.displayName ?? "Nothing Playing")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let artist = song?.artistName, !artist.isEmpty {
                        Text(artist.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .kerning(1.5)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: artSize, alignment: .topLeading)

                Spacer(minLength: 0)
            }

            // Hairline progress rule
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.surface.opacity(0.6))
                        .frame(height: 1)
                    Rectangle()
                        .fill(palette?.primary ?? AppTheme.dynamicAccent)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))), height: 1)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: 1)
        }
        .frame(width: totalWidth)
        .onChange(of: isPlaying) { playing in
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                breathe = playing
            }
            if !playing {
                withAnimation(.easeOut(duration: 0.5)) { breathe = false }
            }
        }
        .onAppear {
            if isPlaying {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            }
        }
        .task(id: song?.id) { await loadPalette() }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let song {
            ArtworkThumbnail(song: song, size: artSize)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
    }
}
