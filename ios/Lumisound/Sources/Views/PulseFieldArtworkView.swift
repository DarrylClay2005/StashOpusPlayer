import SwiftUI

// MARK: - PulseFieldArtworkView
//
// A square cover sits between two rows of small equalizer cells that pulse
// in a smooth wave pattern, colored from the artwork's palette. The cover
// itself breathes gently while playing. Replaces the radial spectrum
// visualization with a calmer, grid-based one.

struct PulseFieldArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var cellLevels: [CGFloat]
    @State private var timer: Timer? = nil
    @State private var artScale: CGFloat = 1.0
    @State private var glow = false
    @State private var palette: ArtworkPalette?

    private let cols = 12
    private let artSize: CGFloat = 200
    private let cellWidth: CGFloat = 8
    private let cellSpacing: CGFloat = 4
    private let minCellHeight: CGFloat = 4
    private let maxCellHeight: CGFloat = 26

    init(song: Song?, isPlaying: Bool) {
        self.song = song
        self.isPlaying = isPlaying
        _cellLevels = State(initialValue: (0..<24).map { i in
            0.2 + 0.3 * abs(sin(Double(i) * 0.5))
        })
    }

    var body: some View {
        VStack(spacing: 14) {
            cellRow(offset: 0)
            centralArt
            cellRow(offset: 12)
        }
        .onChange(of: isPlaying) { playing in
            if playing { startTimer() } else { stopTimer() }
        }
        .onChange(of: scenePhase) { phase in
            // Background audio keeps the run loop alive, so this 12.5Hz timer
            // would otherwise keep recomputing cell levels with nothing on
            // screen to show for it. Just pause/resume the ticking.
            if phase == .active {
                if isPlaying { startTimer() }
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
        .onAppear {
            if isPlaying { startTimer() }
        }
        .onDisappear {
            stopTimer()
        }
        .task(id: song?.id) {
            await loadPalette()
        }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    private func cellRow(offset: Int) -> some View {
        HStack(spacing: cellSpacing) {
            ForEach(0..<cols, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(cellColor(index: i))
                    .frame(
                        width: cellWidth,
                        height: minCellHeight + (maxCellHeight - minCellHeight) * cellLevels[offset + i]
                    )
                    .animation(.easeInOut(duration: 0.08), value: cellLevels[offset + i])
            }
        }
        .frame(height: maxCellHeight, alignment: .center)
    }

    private func cellColor(index: Int) -> Color {
        let base = index % 2 == 0
            ? (palette?.primary ?? AppTheme.dynamicAccent)
            : (palette?.secondary ?? AppTheme.accentSoft)
        return base.opacity(isPlaying ? 0.85 : 0.35)
    }

    private var centralArt: some View {
        Group {
            if let song {
                ArtworkThumbnail(song: song, size: artSize)
                    .environmentObject(library)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                            .font(.system(size: 60, weight: .semibold))
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(artScale)
        .shadow(
            color: (palette?.primary ?? AppTheme.dynamicAccent).opacity(glow ? 0.4 : 0.15),
            radius: glow ? 26 : 14, x: 0, y: 8
        )
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: glow)
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: artScale)
    }

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
    }

    // MARK: Timer

    private func startTimer() {
        stopTimer()
        glow = true
        artScale = 1.015

        let t = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            for i in 0..<cellLevels.count {
                let phase = Double(i) / Double(cellLevels.count) * 2 * .pi
                let drift = 0.5 + 0.45 * sin(now * 3.2 + phase)
                let jitter = Double.random(in: -0.08...0.08)
                cellLevels[i] = CGFloat(max(0.05, min(1.0, drift + jitter)))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        glow = false
        artScale = 1.0
        withAnimation(.easeOut(duration: 0.6)) {
            for i in 0..<cellLevels.count {
                cellLevels[i] = 0.2 + 0.3 * abs(sin(Double(i) * 0.5))
            }
        }
    }
}
