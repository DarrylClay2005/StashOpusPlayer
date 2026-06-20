import SwiftUI

// MARK: - EditorialArtworkView
//
// A bold magazine/poster spread: an oversized, faded title sits behind the
// layout as a graphic element, the cover anchors the top-left with a heavy drop
// shadow, a thick accent rail runs down the side, and a full-width hairline
// progress rule tracks playback. Stronger typographic hierarchy than a plain
// art card.

struct EditorialArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    /// Playback progress in [0, 1]. Pass 0 if unavailable.
    var progress: Double = 0

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var breathe = false

    private let artSize: CGFloat = 158
    private let totalWidth: CGFloat = 320
    private let totalHeight: CGFloat = 320

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Oversized faded background word — a graphic poster element.
            Text(song?.displayName ?? "LUMISOUND")
                .font(.system(size: 86, weight: .black, design: .rounded))
                .foregroundStyle((palette?.primary ?? AppTheme.dynamicAccent).opacity(0.12))
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .frame(width: totalWidth, height: totalHeight, alignment: .bottomTrailing)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    // Thick accent rail.
                    Rectangle()
                        .fill(
                            LinearGradient(colors: [palette?.primary ?? AppTheme.dynamicAccent,
                                                    palette?.secondary ?? AppTheme.accentSoft],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 6, height: artSize)
                        .clipShape(Capsule())

                    artworkContent
                        .frame(width: artSize, height: artSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                        .scaleEffect(breathe ? 1.015 : 1.0)
                        .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 12)

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NOW PLAYING")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(palette?.primary ?? AppTheme.dynamicAccent)
                        .kerning(3)

                    Text(song?.displayName ?? "Nothing Playing")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let artist = song?.artistName, !artist.isEmpty {
                        Text(artist.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .kerning(2)
                            .lineLimit(1)
                    }
                }

                // Full-width hairline progress rule.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.surface.opacity(0.6)).frame(height: 2)
                        Capsule()
                            .fill(palette?.primary ?? AppTheme.dynamicAccent)
                            .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))), height: 2)
                            .animation(.easeInOut(duration: 0.2), value: progress)
                    }
                }
                .frame(height: 2)
            }
            .frame(width: totalWidth, alignment: .leading)
        }
        .frame(width: totalWidth, height: totalHeight)
        .onChange(of: isPlaying) { playing in
            if playing {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathe = true }
            } else {
                withAnimation(.easeOut(duration: 0.5)) { breathe = false }
            }
        }
        .onAppear {
            if isPlaying {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathe = true }
            }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    @ViewBuilder
    private var artworkContent: some View {
        if let song {
            ArtworkThumbnail(song: song, size: artSize)
                .environmentObject(library)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.surface, AppTheme.elevatedSurface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: artSize, height: artSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
        }
    }
}
