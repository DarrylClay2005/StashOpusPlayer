import SwiftUI

// MARK: - TicketStubArtworkView
//
// The artwork is presented as a concert ticket: a stub on the left holds the
// cover art, a perforated edge separates it from the main body, and the
// body shows the track/artist with a faux barcode along the bottom. A scan
// line sweeps the barcode while playing.

struct TicketStubArtworkView: View {
    let song: Song?
    let isPlaying: Bool

    @EnvironmentObject private var library: LibraryManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var floating = false
    @State private var scanOffset: CGFloat = -40
    @State private var palette: ArtworkPalette?

    private let ticketWidth: CGFloat = 320
    private let ticketHeight: CGFloat = 160
    private let stubWidth: CGFloat = 120

    private static let barWidths: [CGFloat] = {
        var generator = SeededRandom(seed: 4_242)
        return (0..<32).map { _ in
            generator.nextDouble() < 0.4 ? 4 : 2
        }
    }()

    var body: some View {
        ZStack {
            TicketShape(stubWidth: stubWidth, notchRadius: 9, cornerRadius: 16)
                .fill(AppTheme.surface, style: FillStyle(eoFill: true))
                .overlay(
                    TicketShape(stubWidth: stubWidth, notchRadius: 9, cornerRadius: 16)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )

            HStack(spacing: 0) {
                stubContent
                    .frame(width: stubWidth, height: ticketHeight)

                perforation

                bodyContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .frame(width: ticketWidth, height: ticketHeight)
        }
        .frame(width: ticketWidth, height: ticketHeight)
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: floating ? 24 : 14, x: 0, y: floating ? 14 : 8)
        .offset(y: floating ? -6 : 0)
        .onAppear { if isPlaying { startAnimations() } }
        .onChange(of: isPlaying) { playing in
            if playing { startAnimations() } else { stopAnimations() }
        }
        .onChange(of: scenePhase) { phase in
            // Background audio keeps the run loop (and this animation's
            // implicit repeat) alive with nothing visible — pausing on
            // background avoids burning cycles on an off-screen sweep.
            if phase == .active {
                if isPlaying { startScan() }
            } else {
                scanOffset = -40
            }
        }
        .task(id: song?.id) {
            await loadPalette()
        }
        .animation(.easeInOut(duration: 1.2), value: palette)
    }

    // MARK: Stub (artwork side)

    private var stubContent: some View {
        ZStack {
            Group {
                if let song {
                    ArtworkThumbnail(song: song, size: stubWidth - 24)
                        .environmentObject(library)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.elevatedSurface, AppTheme.surface],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: stubWidth - 24, height: stubWidth - 24)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }
                }
            }
            .frame(width: stubWidth - 24, height: stubWidth - 24)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Perforation

    private var perforation: some View {
        VStack(spacing: 6) {
            ForEach(0..<11, id: \.self) { _ in
                Circle()
                    .fill(AppTheme.textSecondary.opacity(0.22))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(width: 14, height: ticketHeight)
    }

    // MARK: Body (info + barcode)

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ADMIT ONE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette?.primary ?? AppTheme.dynamicAccent)
                .kerning(2.5)

            Text(song?.displayName ?? "Nothing Playing")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let artist = song?.artistName, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            barcode
        }
    }

    private var barcode: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 2) {
                ForEach(Array(Self.barWidths.enumerated()), id: \.offset) { _, w in
                    Rectangle()
                        .fill(AppTheme.textPrimary.opacity(0.55))
                        .frame(width: w)
                }
            }
            if isPlaying {
                Rectangle()
                    .fill((palette?.primary ?? AppTheme.dynamicAccent).opacity(0.55))
                    .frame(width: 3)
                    .offset(x: scanOffset)
            }
        }
        .frame(height: 24, alignment: .leading)
        .clipped()
    }

    // MARK: Helpers

    private func loadPalette() async {
        palette = await ArtworkPaletteLoader.palette(for: song, library: library)
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            floating = true
        }
        startScan()
    }

    private func stopAnimations() {
        withAnimation(.easeOut(duration: 0.5)) {
            floating = false
        }
        scanOffset = -40
    }

    private func startScan() {
        scanOffset = -40
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            scanOffset = 200
        }
    }
}

// MARK: - TicketShape

/// A rounded rectangle with two small semicircular notches cut into its top
/// and bottom edges at `stubWidth`, suggesting a torn perforation line.
struct TicketShape: Shape {
    let stubWidth: CGFloat
    let notchRadius: CGFloat
    var cornerRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius)
        let x = rect.minX + stubWidth
        let topNotch = CGRect(x: x - notchRadius, y: rect.minY - notchRadius, width: notchRadius * 2, height: notchRadius * 2)
        let bottomNotch = CGRect(x: x - notchRadius, y: rect.maxY - notchRadius, width: notchRadius * 2, height: notchRadius * 2)
        path.addPath(Path(ellipseIn: topNotch))
        path.addPath(Path(ellipseIn: bottomNotch))
        return path
    }
}
