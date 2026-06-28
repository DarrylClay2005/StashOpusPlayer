import SwiftUI

// MARK: - OrigamiArtworkView — "Spotlight Stage"
//
// The cover on a dark stage lit by two soft spotlight beams that slowly sweep,
// with a palette glow and a fading floor reflection.
struct OrigamiArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var sweep = false

    private var tint: Color { palette?.primary ?? AppTheme.dynamicAccent }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [.black, Color(white: 0.08)], startPoint: .top, endPoint: .bottom))

            ForEach(0..<2) { i in
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 70, height: 330)
                    .rotationEffect(.degrees((i == 0 ? -1 : 1) * (sweep ? 16 : 28)), anchor: .top)
                    .offset(y: -12)
                    .blur(radius: 16)
                    .blendMode(.plusLighter)
            }

            VStack(spacing: 4) {
                StyleCover(song: song, size: 230, cornerRadius: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: tint.opacity(0.5), radius: 26)

                ArtworkReflectionView(song: song, size: 230, cornerRadius: 16)
                    .environmentObject(library)
            }
        }
        .frame(width: 320, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.2))
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { sweep = true }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
