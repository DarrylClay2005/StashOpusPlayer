import SwiftUI

struct RingScrubberView: View {
    let position: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragAngle: Double? = nil
    @State private var ringGlow = false
    @State private var outerRotation: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        if let angle = dragAngle {
            return min(max(angle / (2 * .pi), 0), 1)
        }
        return min(1, position / duration)
    }

    private var displayPosition: TimeInterval {
        dragAngle.map { min(max($0 / (2 * .pi), 0), 1) * duration } ?? position
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                // Track/progress `Circle()` shapes below have no explicit frame, so they
                // inscribe in the full geo box — their stroke centerline sits at exactly
                // half the box's shorter side. The thumb dot's offset must match that
                // radius (not an inset version) or it visibly floats inside the ring
                // instead of riding along the progress arc.
                let radius = min(geo.size.width, geo.size.height) / 2

                ZStack {
                    // Outer decorative dashed ring — rotates while playing
                    Circle()
                        .strokeBorder(
                            AppTheme.dynamicAccent.opacity(ringGlow ? 0.22 : 0.08),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 7])
                        )
                        .rotationEffect(.degrees(outerRotation))

                    // Track ring
                    Circle()
                        .stroke(AppTheme.surface, lineWidth: 10)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.accentSoft, AppTheme.dynamicAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(
                            color: AppTheme.dynamicAccent.opacity(ringGlow ? 0.55 : 0.15),
                            radius: ringGlow ? 8 : 2
                        )
                        .animation(dragAngle == nil ? .easeInOut(duration: 0.12) : nil, value: progress)

                    // Thumb dot — positioning (offset/rotation) and the glow pulse are
                    // applied on separate nested views. A `repeatForever` animation on
                    // one view applies to ALL of that view's animatable properties, so
                    // putting the pulse's `.animation(repeatForever, value: ringGlow)`
                    // on the same view as the rotation caused the thumb's position to
                    // get dragged along by the perpetual pulse curve instead of the
                    // quick progress animation — which is why the ball visibly lagged
                    // behind the actual playback time.
                    Group {
                        Circle()
                            .fill(AppTheme.dynamicAccent)
                            .frame(width: 16, height: 16)
                            .shadow(
                                color: AppTheme.dynamicAccent.opacity(ringGlow ? 0.8 : 0.4),
                                radius: ringGlow ? 10 : 4
                            )
                            .scaleEffect(ringGlow ? 1.15 : 1.0)
                            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: ringGlow)
                    }
                    .offset(y: -radius)
                    // The base offset `(0, -radius)` already sits at the top (12
                    // o'clock), which is where the progress arc's `trim(from:0,
                    // to:_)` starts after its own `-90°` rotation (see the arc
                    // above). So the thumb must sweep from that same zero point —
                    // applying an additional `-90°` here rotated the thumb a
                    // quarter turn ahead of the arc, putting it at 9 o'clock when
                    // progress was ~0 instead of riding the arc's tip at 12.
                    .rotationEffect(.degrees(progress * 360))
                    // Match the progress arc's animation so the thumb glides along
                    // with the fill instead of snapping to each playback tick while
                    // the arc behind it eases smoothly — the mismatch read as the
                    // thumb "jumping" independently of the ring. Disabled while
                    // dragging so the thumb tracks the finger 1:1.
                    .animation(dragAngle == nil ? .easeInOut(duration: 0.12) : nil, value: progress)

                    // Time display
                    VStack(spacing: 2) {
                        Text(formatTime(displayPosition))
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(formatTime(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let dx = val.location.x - center.x
                            let dy = val.location.y - center.y
                            var angle = atan2(dy, dx) + .pi / 2
                            if angle < 0 { angle += 2 * .pi }
                            dragAngle = angle
                        }
                        .onEnded { val in
                            let dx = val.location.x - center.x
                            let dy = val.location.y - center.y
                            var angle = atan2(dy, dx) + .pi / 2
                            if angle < 0 { angle += 2 * .pi }
                            let frac = min(max(angle / (2 * .pi), 0), 1)
                            onSeek(frac * duration)
                            dragAngle = nil
                        }
                )
            }
            .frame(width: 200, height: 200)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onAppear {
            updateAnimations(playing: isPlaying)
        }
    }

    private func updateAnimations(playing: Bool) {
        ringGlow = playing
        if playing {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                outerRotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.5)) {
                outerRotation = 0
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        t.formattedAsMinutesSeconds
    }
}
