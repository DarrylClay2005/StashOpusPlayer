import SwiftUI

// MARK: - TicketStubArtworkView — "Radial Spectrum"
//
// A circular cover ringed by a radial spectrum of bars pulsing outward.
struct TicketStubArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @State private var active = false

    private let count = 56
    private var tint: Color { palette?.primary ?? AppTheme.dynamicAccent }
    private var tint2: Color { palette?.secondary ?? AppTheme.accentSoft }

    private func len(_ i: Int) -> CGFloat { CGFloat(16 + (i * 41) % 40) }
    private func dur(_ i: Int) -> Double { 0.6 + Double((i * 29) % 70) / 100.0 }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint2], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: active ? len(i) : 8)
                    .offset(y: -148)
                    .rotationEffect(.degrees(Double(i) / Double(count) * 360))
                    .animation(.easeInOut(duration: dur(i)).repeatForever(autoreverses: true), value: active)
            }

            StyleCover(song: song, size: 210, cornerRadius: 105)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: tint.opacity(0.5), radius: 24)
        }
        .frame(width: 330, height: 330)
        .modifier(FloatModifier(isPlaying: isPlaying, amount: 5, speed: 3.2))
        .onAppear { active = isPlaying }
        .onChange(of: isPlaying) { active = $0 }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song, library: library) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }
}
