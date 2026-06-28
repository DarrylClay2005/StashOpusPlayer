import SwiftUI

// MARK: - PulseFieldArtworkView — "Spectrum Bars"
//
// The cover above a live spectrum-analyzer row of bars dancing at varied rates.
struct PulseFieldArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var active = false

    private let count = 26
    private var c1: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var c2: Color { palette?.secondary ?? AppTheme.accentSoft }

    // Deterministic per-bar tall height + animation duration.
    private func tall(_ i: Int) -> CGFloat { CGFloat(22 + (i * 53) % 56) }
    private func dur(_ i: Int) -> Double { 0.5 + Double((i * 37) % 60) / 100.0 }

    var body: some View {
        VStack(spacing: 16) {
            StyleCover(song: song, size: 250, cornerRadius: 20)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: c1.opacity(0.4), radius: 24, y: 12)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [c2, c1], startPoint: .bottom, endPoint: .top))
                        .frame(width: 6, height: active ? tall(i) : 8)
                        .animation(.easeInOut(duration: dur(i)).repeatForever(autoreverses: true), value: active)
                }
            }
            .frame(height: 80)
        }
        .frame(width: 320, height: 360)
        .onAppear { active = isPlaying }
        .onChange(of: isPlaying) { active = $0 }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
