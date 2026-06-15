import SwiftUI

struct NeonGlowArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    @EnvironmentObject private var library: LibraryManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var glowPhase: Double = 0
    @State private var ringScales: [CGFloat] = [1.0, 1.0, 1.0, 1.0, 1.0]
    @State private var outerRotation: Double = 0
    @State private var breatheTimer: Timer? = nil

    private let ringDiameters: [CGFloat] = [300, 270, 240, 214, 186]
    private let ringWidths: [CGFloat]    = [2.5, 2.0, 2.5, 1.5, 2.0]
    private let breatheSpeeds: [Double]  = [2.6, 3.4, 2.1, 3.8, 2.9]

    var body: some View {
        ZStack {
            // Outer slowly rotating rings
            ForEach(0..<5) { i in
                let hue = (glowPhase + Double(i) * 0.20).truncatingRemainder(dividingBy: 1)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hue: hue, saturation: 1, brightness: 1),
                                Color(hue: (hue + 0.14).truncatingRemainder(dividingBy: 1),
                                      saturation: 0.7, brightness: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: ringWidths[i]
                    )
                    .frame(width: ringDiameters[i], height: ringDiameters[i])
                    .scaleEffect(ringScales[i])
                    .blur(radius: i < 3 ? 5 : 3)
                    .opacity(isPlaying ? 0.62 : 0.25)
                    .rotationEffect(.degrees(outerRotation * (i % 2 == 0 ? 1 : -1)))
                    .animation(.easeInOut(duration: breatheSpeeds[i]).repeatForever(autoreverses: true), value: ringScales[i])
            }

            // Central artwork
            Group {
                if let song {
                    ArtworkThumbnail(song: song, size: 210)
                        .environmentObject(library)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hue: glowPhase, saturation: 1, brightness: 0.8),
                                    Color(hue: (glowPhase + 0.35).truncatingRemainder(dividingBy: 1),
                                          saturation: 0.8, brightness: 0.35)
                                ],
                                center: .center,
                                startRadius: 20,
                                endRadius: 105
                            )
                        )
                        .frame(width: 210, height: 210)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 60, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }
            }
            // Neon-tube bloom — several copies of the same stroked ring at
            // increasing blur radii and decreasing opacity, stacked behind
            // the crisp tube outline. This is what gives true neon signage
            // its glowing "halo" rather than a single flat shadow.
            ForEach([18, 12, 6], id: \.self) { radius in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hue: glowPhase, saturation: 1, brightness: 1),
                                Color(hue: (glowPhase + 0.5).truncatingRemainder(dividingBy: 1),
                                      saturation: 1, brightness: 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 210, height: 210)
                    .blur(radius: CGFloat(radius))
                    .opacity((isPlaying ? 0.5 : 0.2) * (1 - Double(radius) / 24))
                    .allowsHitTesting(false)
            }

            // Crisp neon-tube outline on top of the bloom
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hue: glowPhase, saturation: 1, brightness: 1),
                            Color(hue: (glowPhase + 0.5).truncatingRemainder(dividingBy: 1),
                                  saturation: 1, brightness: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 210, height: 210)
        }
        .overlay(
            Circle()
                .stroke(.white.opacity(isPlaying ? 0.5 : 0.2), lineWidth: 1)
                .frame(width: 210, height: 210)
                .blur(radius: 1)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isPlaying)
        )
        .frame(width: 310, height: 310)
        .onChange(of: isPlaying) { playing in
            updateAnimations(playing: playing)
        }
        .onChange(of: scenePhase) { phase in
            // The breathe timer keeps firing on the run loop while the app is
            // backgrounded (background audio keeps the process alive), burning
            // CPU on an animation nobody can see. Pause it without resetting
            // ring scales so playback resumes the visual state, not a reset.
            if phase == .active {
                if isPlaying { startBreathe() }
            } else {
                breatheTimer?.invalidate()
                breatheTimer = nil
            }
        }
        .onAppear {
            startHueRotation()
            updateAnimations(playing: isPlaying)
        }
        .onDisappear {
            breatheTimer?.invalidate()
            breatheTimer = nil
        }
    }

    private func startHueRotation() {
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            glowPhase = 1
        }
    }

    private func updateAnimations(playing: Bool) {
        if playing {
            startBreathe()
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                outerRotation = 360
            }
        } else {
            breatheTimer?.invalidate()
            breatheTimer = nil
            withAnimation(.easeOut(duration: 0.6)) {
                for i in 0..<5 { ringScales[i] = 1.0 }
                outerRotation = 0
            }
        }
    }

    private func startBreathe() {
        breatheTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            for i in 0..<5 {
                let phase = Double(i) * 0.62 + now / breatheSpeeds[i]
                ringScales[i] = CGFloat(1.0 + 0.07 * sin(phase * 2 * .pi))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        breatheTimer = t
    }
}
