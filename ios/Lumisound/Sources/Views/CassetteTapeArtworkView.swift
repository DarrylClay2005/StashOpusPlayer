import SwiftUI

struct CassetteTapeArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    @EnvironmentObject private var library: LibraryManager

    @State private var spoolRotation: Double = 0
    @State private var floating = false
    @State private var vuWidth: CGFloat = 60
    @State private var vuTimer: Timer? = nil
    @State private var tapeShimmer: CGFloat = 0

    var body: some View {
        ZStack {
            // Tape housing
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.13, green: 0.13, blue: 0.17),
                                 Color(red: 0.20, green: 0.20, blue: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 300, height: 188)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(white: 0.32).opacity(0.45), lineWidth: 1)
                )
                .shadow(
                    color: AppTheme.dynamicAccent.opacity(floating ? 0.25 : 0.08),
                    radius: floating ? 28 : 16,
                    x: 0, y: 10
                )
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: floating)

            // Label
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.surface)
                .frame(width: 194, height: 86)
                .overlay {
                    if let song {
                        ArtworkThumbnail(song: song, size: 194)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .opacity(0.7)
                    }
                    VStack(spacing: 3) {
                        Text(song?.displayName ?? "No Track")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.85), radius: 4)
                        Text(song?.artistName ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.85), radius: 4)
                    }
                    .padding(.horizontal, 10)
                }
                .offset(y: -18)

            // Left spool
            spoolView
                .offset(x: -72, y: 54)

            // Right spool
            spoolView
                .offset(x: 72, y: 54)

            // Tape window with moving tape highlight
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.06, blue: 0.08))
                    .frame(width: 150, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(white: 0.2), lineWidth: 1)
                    )

                // Tape movement shimmer — a soft horizontal sweep
                if isPlaying {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color(white: 0.35).opacity(0.5), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 40, height: 14)
                        .offset(x: tapeShimmer)
                        .clipped()
                }
            }
            .frame(width: 150, height: 24)
            .clipped()
            .offset(y: 54)

            // VU meter accent stripe — width pulses while playing
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(AppTheme.dynamicAccent)
                .frame(width: vuWidth, height: 3)
                .animation(.easeInOut(duration: 0.08), value: vuWidth)
                .offset(y: 82)
        }
        .frame(width: 300, height: 200)
        .offset(y: floating ? -6 : 0)
        .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: floating)
        .onChange(of: isPlaying) { playing in
            if playing { startAnimations() } else { stopAnimations() }
        }
        .onAppear {
            if isPlaying { startAnimations() }
        }
        .onDisappear {
            stopAnimations()
        }
    }

    private var spoolView: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.10))
                .frame(width: 48, height: 48)
                .overlay(
                    Circle()
                        .strokeBorder(Color(white: 0.25), lineWidth: 1)
                )

            ForEach(0..<6) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(white: 0.38))
                    .frame(width: 3, height: 12)
                    .offset(y: -12)
                    .rotationEffect(.degrees(Double(i) * 60))
            }

            Circle()
                .fill(Color(white: 0.18))
                .frame(width: 14, height: 14)
        }
        .rotationEffect(.degrees(spoolRotation))
    }

    private func startAnimations() {
        // Spool rotation
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            spoolRotation = 360
        }
        // Housing float
        floating = true
        // Tape shimmer sweep
        startTapeShimmer()
        // VU meter
        startVU()
    }

    private func stopAnimations() {
        withAnimation(.easeOut(duration: 0.5)) {
            floating = false
        }
        withAnimation(.easeOut(duration: 0.3)) {
            vuWidth = 60
            tapeShimmer = 0
        }
        vuTimer?.invalidate()
        vuTimer = nil
    }

    private func startTapeShimmer() {
        tapeShimmer = -80
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            tapeShimmer = 80
        }
    }

    private func startVU() {
        vuTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            let now = Date().timeIntervalSince1970
            let base = 40.0 + 26.0 * abs(sin(now * 4.2))
            let jitter = Double.random(in: -6...6)
            vuWidth = CGFloat(max(20, min(80, base + jitter)))
        }
        RunLoop.main.add(t, forMode: .common)
        vuTimer = t
    }
}
