import SwiftUI

// MARK: - PulseFieldArtworkView — "Spectrum Bars"
//
// The cover above a bold, glowing spectrum-analyzer row (with a faint mirrored
// reflection) whose bars dance at varied rates.
struct PulseFieldArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var active = false

    private let count = 22
    private var c1: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var c2: Color { palette?.secondary ?? AppTheme.accentSoft }

    // Deterministic per-bar tall/rest height + animation duration.
    private func tall(_ i: Int) -> CGFloat { CGFloat(46 + (i * 53) % 56) }
    private func rest(_ i: Int) -> CGFloat { CGFloat(18 + (i * 17) % 16) }
    private func dur(_ i: Int) -> Double { 0.45 + Double((i * 37) % 60) / 100.0 }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [c2, c1, .white], startPoint: .bottom, endPoint: .top))
                    .frame(width: 8, height: active ? tall(i) : rest(i))
                    .shadow(color: c1.opacity(0.6), radius: 4)
                    .animation(.easeInOut(duration: dur(i)).repeatForever(autoreverses: true), value: active)
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            StyleCover(song: song, size: 250, cornerRadius: 20)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: c1.opacity(0.45), radius: 26, y: 12)

            VStack(spacing: 0) {
                bars.frame(height: 100, alignment: .bottom)
                bars
                    .frame(height: 36, alignment: .top)
                    .scaleEffect(y: -1, anchor: .top)
                    .opacity(0.22)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(width: 320, height: 380)
        .onAppear { active = isPlaying }
        .onChange(of: isPlaying) { active = $0 }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
