import SwiftUI

struct CassetteTapeArtworkView: View {
    let song: Song?
    let isPlaying: Bool
    @EnvironmentObject private var library: LibraryManager

    @State private var spoolRotation: Double = 0

    var body: some View {
        ZStack {
            // Tape housing
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.13, green: 0.13, blue: 0.17), Color(red: 0.20, green: 0.20, blue: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 300, height: 188)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(white: 0.32).opacity(0.45), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)

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

            // Tape window
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: 0.06, green: 0.06, blue: 0.08))
                .frame(width: 150, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color(white: 0.2), lineWidth: 1)
                )
                .offset(y: 54)

            // Accent stripe at bottom edge of housing
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(AppTheme.dynamicAccent)
                .frame(width: 60, height: 3)
                .offset(y: 82)
        }
        .frame(width: 300, height: 200)
        .onChange(of: isPlaying) { playing in
            if playing { startSpools() } else { stopSpools() }
        }
        .onAppear {
            if isPlaying { startSpools() }
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

    private func startSpools() {
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            spoolRotation = 360
        }
    }

    private func stopSpools() {
        withAnimation(.easeOut(duration: 0.5)) { }
    }
}
