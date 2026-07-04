import SwiftUI

// MARK: - CustomStyleArtworkView
//
// Generic renderer for user-created custom Now Playing styles. Unlike the
// 19 built-in styles (each its own hand-written view), this one interprets
// a `CustomNowPlayingStyle` value at runtime — every visual is driven by
// `TimelineView`/`ArtworkClock` (the same freeze-proof pattern used
// throughout the built-in styles) rather than per-style bespoke state.
struct CustomStyleArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    let config: CustomNowPlayingStyle

    @EnvironmentObject private var library: LibraryManager
    @State private var palette: ArtworkPalette?
    @ObservedObject private var visualizer = AudioVisualizerService.shared

    private var accentColor: Color {
        switch config.accentSource {
        case .palette: return palette?.primary ?? AppTheme.dynamicAccent
        case .custom:  return config.customAccentColor.color
        }
    }

    private var coverShape: some Shape {
        config.coverShape == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                backgroundView
                decorationView(t: t)
                coverView(t: t)
            }
            .frame(width: 300, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .onAppear { startWaveformIfNeeded() }
        .onDisappear { visualizer.stop() }
        .onChange(of: isPlaying) { playing in
            guard config.decoration == .waveform else { return }
            if playing { visualizer.start() } else { visualizer.stop() }
        }
        .task(id: song?.id) { palette = await ArtworkPaletteLoader.palette(for: song) }
        .animation(.easeInOut(duration: 1.0), value: palette)
    }

    private func startWaveformIfNeeded() {
        guard config.decoration == .waveform, isPlaying else { return }
        visualizer.start()
    }

    // MARK: Background

    @ViewBuilder
    private var backgroundView: some View {
        switch config.backgroundKind {
        case .ambient:
            AmbientArtworkBackground(song: song)
                .environmentObject(library)
        case .solid:
            config.backgroundColor1.color
        case .gradient:
            LinearGradient(
                colors: [config.backgroundColor1.color, config.backgroundColor2.color],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .dark:
            Color(red: 0.06, green: 0.06, blue: 0.08)
        case .light:
            Color(red: 0.9, green: 0.9, blue: 0.92)
        }
    }

    // MARK: Cover (shape/border/shadow/animation)

    @ViewBuilder
    private func coverView(t: TimeInterval) -> some View {
        let phase = ArtworkClock.pingPong(Date(timeIntervalSinceReferenceDate: t), legDuration: 2.6 / config.animationSpeed)
        let loopPhase = ArtworkClock.loop(Date(timeIntervalSinceReferenceDate: t), cycleDuration: 8.0 / config.animationSpeed)

        StyleCover(song: song, size: config.coverSize, cornerRadius: config.coverShape == .circle ? config.coverSize / 2 : config.cornerRadius)
            .clipShape(coverShape)
            .overlay {
                if config.borderStyle != .none {
                    coverShape.stroke(
                        config.borderUsesAccent ? accentColor : config.borderColor.color,
                        lineWidth: config.borderStyle.lineWidth
                    )
                }
            }
            .modifier(ShadowModifier(style: config.shadowStyle, color: accentColor))
            .modifier(CoverAnimationModifier(animation: config.coverAnimation, phase: phase, loopPhase: loopPhase))
    }

    // MARK: Decoration

    @ViewBuilder
    private func decorationView(t: TimeInterval) -> some View {
        switch config.decoration {
        case .none:
            EmptyView()
        case .glowRing:
            glowRingDecoration(t: t)
        case .particles:
            particlesDecoration(t: t)
        case .sweep:
            sweepDecoration(t: t)
        case .bars:
            barsDecoration(t: t)
        case .waveform:
            waveformDecoration
        case .blobs:
            blobsDecoration(t: t)
        }
    }

    private func glowRingDecoration(t: TimeInterval) -> some View {
        let phase = ArtworkClock.pingPong(Date(timeIntervalSinceReferenceDate: t), legDuration: 1.6)
        let ringSize: CGFloat = config.coverSize + 20 + phase * 25
        return Circle()
            .stroke(accentColor.opacity(0.5), lineWidth: 3)
            .frame(width: ringSize, height: ringSize)
            .opacity(1 - phase * 0.7)
    }

    private func particlesDecoration(t: TimeInterval) -> some View {
        let angleBase = ArtworkClock.loop(Date(timeIntervalSinceReferenceDate: t), cycleDuration: 10) * 360
        return ForEach(0..<8, id: \.self) { i in
            let angle = (angleBase + Double(i) * 45) * .pi / 180
            let radius = config.coverSize / 2 + 30
            Circle()
                .fill(accentColor)
                .frame(width: 6, height: 6)
                .shadow(color: accentColor, radius: 5)
                .offset(x: cos(angle) * radius, y: sin(angle) * radius * 0.6)
        }
    }

    private func sweepDecoration(t: TimeInterval) -> some View {
        let angle = ArtworkClock.loop(Date(timeIntervalSinceReferenceDate: t), cycleDuration: 4) * 360
        return AngularGradient(
            colors: [accentColor.opacity(0), accentColor.opacity(0.55)],
            center: .center, startAngle: .degrees(angle - 45), endAngle: .degrees(angle)
        )
        .frame(width: 280, height: 280)
        .clipShape(Circle())
    }

    private func barsDecoration(t: TimeInterval) -> some View {
        let phase = ArtworkClock.pingPong(Date(timeIntervalSinceReferenceDate: t), legDuration: 0.5)
        let scale: CGFloat = isPlaying ? 0.5 + phase * 0.5 : 0.4
        return VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(_barRatios.enumerated()), id: \.offset) { _, ratio in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accentColor)
                        .frame(width: 8, height: max(4, 70 * ratio * scale))
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var _barRatios: [CGFloat] {
        var rng = SeededRandom(seed: 7_331)
        return (0..<12).map { _ in 0.35 + CGFloat(rng.nextDouble()) * 0.65 }
    }

    private var waveformDecoration: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(visualizer.magnitudes.enumerated()), id: \.offset) { _, magnitude in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accentColor)
                        .frame(height: max(3, CGFloat(magnitude) * 100))
                }
            }
            .frame(height: 100)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func blobsDecoration(t: TimeInterval) -> some View {
        let phase = ArtworkClock.pingPong(Date(timeIntervalSinceReferenceDate: t), legDuration: 4.5)
        return ZStack {
            Circle().fill(accentColor).blur(radius: 40).opacity(0.5)
                .frame(width: 130, height: 130)
                .offset(x: -80 + phase * 20, y: -70 - phase * 10)
            Circle().fill(config.customAccentColor.color).blur(radius: 40).opacity(0.4)
                .frame(width: 110, height: 110)
                .offset(x: 80 - phase * 20, y: 80 + phase * 10)
        }
    }
}

// MARK: - Shape type erasure (coverShape needs to return either Circle or RoundedRectangle)

private struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { pathBuilder = shape.path(in:) }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

// MARK: - ShadowModifier

private struct ShadowModifier: ViewModifier {
    let style: CustomNowPlayingStyle.ShadowStyle
    let color: Color

    func body(content: Content) -> some View {
        switch style {
        case .none:
            content
        case .soft:
            content.shadow(color: .black.opacity(0.4), radius: 16, y: 10)
        case .strong:
            content
                .shadow(color: .black.opacity(0.6), radius: 24, y: 14)
                .shadow(color: color.opacity(0.5), radius: 26)
        }
    }
}

// MARK: - CoverAnimationModifier

private struct CoverAnimationModifier: ViewModifier {
    let animation: CustomNowPlayingStyle.CoverAnimation
    /// 0...1...0 ping-pong phase, pre-computed period matching the config's speed.
    let phase: Double
    /// 0..<1 continuously looping phase, for the rotate case.
    let loopPhase: Double

    func body(content: Content) -> some View {
        switch animation {
        case .none:
            content
        case .float:
            content.offset(y: -10 * phase)
        case .pulse:
            content.scaleEffect(1.0 + 0.04 * phase)
        case .rotate:
            content.rotationEffect(.degrees(loopPhase * 360))
        case .sway:
            content.rotationEffect(.degrees(-4 + 8 * phase))
        }
    }
}
