import SwiftUI

// MARK: - LiveSpectrumArtworkView — "Live Spectrum"
//
// Unlike the other 18 Now Playing styles (decorative, always-animating
// regardless of what's actually playing), this one is a genuine real-time
// FFT spectrum of the live audio graph via `AudioVisualizerService` — the
// bars are silent/flat when paused and react to the actual track otherwise.
// The tap only runs while this exact view is on-screen (installed in
// onAppear, removed in onDisappear/on pause) so there's no FFT overhead for
// the other 18 styles that don't use it.
struct LiveSpectrumArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @ObservedObject private var visualizer = AudioVisualizerService.shared
    // A scripted `LuaVisualizerEngine.Config`, if the user picked one under
    // Settings > Playback & Audio > Scripted Visualizer — purely a
    // presentation override (gradient/sensitivity/spacing/mirroring); the
    // FFT data itself always comes from `AudioVisualizerService` above.
    @ObservedObject private var luaVisualizer = LuaVisualizerStore.shared

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    private var barColors: [Color] {
        guard let hexColors = luaVisualizer.activeConfig?.colors, !hexColors.isEmpty else {
            return [AppTheme.dynamicAccent, .cyan]
        }
        return hexColors.map { Color(hex: $0) }
    }

    private var displayMagnitudes: [Float] {
        let sensitivity = Float(luaVisualizer.activeConfig?.sensitivity ?? 1.0)
        let scaled = visualizer.magnitudes.map { min(1, max(0, $0 * sensitivity)) }
        return (luaVisualizer.activeConfig?.mirrored ?? false) ? scaled.reversed() : scaled
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.04, green: 0.04, blue: 0.07))

            HStack(alignment: .bottom, spacing: CGFloat(luaVisualizer.activeConfig?.barSpacing ?? 4)) {
                ForEach(Array(displayMagnitudes.enumerated()), id: \.offset) { _, magnitude in
                    RoundedRectangle(cornerRadius: luaVisualizer.activeConfig?.barCornerRadius ?? 2, style: .continuous)
                        .fill(
                            LinearGradient(colors: barColors, startPoint: .bottom, endPoint: .top)
                        )
                        .frame(height: max(4, CGFloat(magnitude) * 150))
                }
            }
            .frame(height: 150, alignment: .bottom)
            .padding(.horizontal, 20)
            .padding(.bottom, 55)

            StyleCover(song: song, size: 150, cornerRadius: 20)
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 12)
                .offset(y: -45)
        }
        .frame(width: 300, height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            if isPlaying { visualizer.start() }
        }
        .onDisappear {
            visualizer.stop()
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                visualizer.start()
            } else {
                visualizer.stop()
            }
        }
    }
}
