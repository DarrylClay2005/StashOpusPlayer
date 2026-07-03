import SwiftUI

// MARK: - EditorialArtworkView — "Minimal Mono"
//
// A clean, gallery-minimal presentation: a crisply-framed cover above a thin
// live progress line with a gliding accent dot. Quiet, typographic, modern.
struct EditorialArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    let progress: Double

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?

    private var tint: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        VStack(spacing: 20) {
            StyleCover(song: song, size: 280, cornerRadius: 6)
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 14)

            GeometryReader { geo in
                let w = max(0, min(1, progress)) * geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14)).frame(height: 3)
                    Capsule().fill(tint).frame(width: w, height: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: 9, height: 9)
                        .shadow(color: tint, radius: 5)
                        .offset(x: w - 4.5)
                }
            }
            .frame(width: 280, height: 9)
        }
        .frame(width: 320, height: 340)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 4, speed: 3.2))
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song) }
        .animation(.easeInOut(duration: 1.0), value: palette)
        .animation(.linear(duration: 0.3), value: progress)
    }
}
