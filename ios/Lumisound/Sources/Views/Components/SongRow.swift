import SwiftUI

// MARK: - SongCardStyle

/// Visual style for the song rows/cards shown throughout the library, queue,
/// favorites, playlists, and artist screens — user-selectable in Appearance
/// settings (`library_cardStyle`) so every `SongRow` call site picks up the
/// chosen look without each screen needing its own rendering logic.
enum SongCardStyle: String, CaseIterable, Identifiable {
    case compact
    case comfortable
    case card
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:     return "Compact"
        case .comfortable: return "Comfortable"
        case .card:        return "Card"
        case .minimal:     return "Minimal"
        }
    }

    var iconName: String {
        switch self {
        case .compact:     return "list.bullet"
        case .comfortable: return "rectangle.grid.1x2"
        case .card:        return "rectangle.on.rectangle.angled"
        case .minimal:     return "minus"
        }
    }
}

struct SongRow: View {
    let song: Song
    let isCurrent: Bool
    var showArtwork: Bool = true
    var subtitle: String? = nil

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    @AppStorage("library_cardStyle") private var cardStyleRaw: String = SongCardStyle.compact.rawValue

    private var style: SongCardStyle {
        SongCardStyle(rawValue: cardStyleRaw) ?? .compact
    }

    private var resolvedSubtitle: String {
        subtitle ?? "\(song.artistName) · \(song.albumName)"
    }

    var body: some View {
        Group {
            switch style {
            case .compact:     compactBody
            case .comfortable: comfortableBody
            case .card:        cardBody
            case .minimal:     minimalBody
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            SongContextMenuContent(song: song)
                .environmentObject(library)
                .environmentObject(player)
        }
    }

    // MARK: - Style variants

    /// The original look — tight single-line row, 44pt artwork.
    private var compactBody: some View {
        HStack(spacing: 12) {
            if showArtwork { artwork(size: 44) }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayName)
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)

                Text(resolvedSubtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            durationLabel(.caption)
        }
        .padding(.vertical, 4)
    }

    /// More breathing room — bigger artwork and type, generous vertical padding.
    private var comfortableBody: some View {
        HStack(spacing: 14) {
            if showArtwork { artwork(size: 56) }

            VStack(alignment: .leading, spacing: 4) {
                Text(song.displayName)
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .font(.callout)
                    .fontWeight(isCurrent ? .bold : .semibold)
                    .lineLimit(1)

                Text(resolvedSubtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            durationLabel(.footnote)
        }
        .padding(.vertical, 9)
    }

    /// Each row rendered as its own elevated, rounded card with an accent
    /// outline when it's the currently-playing track.
    private var cardBody: some View {
        HStack(spacing: 14) {
            if showArtwork { artwork(size: 60, cornerRadius: 12) }

            VStack(alignment: .leading, spacing: 4) {
                Text(song.displayName)
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(resolvedSubtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            durationLabel(.footnote)
        }
        .padding(12)
        .background(
            isCurrent ? AppTheme.dynamicAccent.opacity(0.14) : AppTheme.elevatedSurface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isCurrent ? AppTheme.dynamicAccent.opacity(0.5) : .clear, lineWidth: 1.5)
        }
        .padding(.vertical, 4)
    }

    /// Dense, text-forward layout — small artwork, tight line spacing, for
    /// users who'd rather see more tracks per screen.
    private var minimalBody: some View {
        HStack(spacing: 10) {
            if showArtwork { artwork(size: 32, cornerRadius: 5) }

            VStack(alignment: .leading, spacing: 1) {
                Text(song.displayName)
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .font(.subheadline)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)

                Text(resolvedSubtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            durationLabel(.caption2)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Shared pieces

    private func artwork(size: CGFloat, cornerRadius: CGFloat? = nil) -> some View {
        Group {
            if let cornerRadius {
                ArtworkThumbnail(song: song, size: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                ArtworkThumbnail(song: song, size: size)
            }
        }
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: cornerRadius ?? 6, style: .continuous)
                    .fill(AppTheme.dynamicAccent.opacity(0.7))
                WaveformIcon()
            }
        }
    }

    private func durationLabel(_ font: Font) -> some View {
        Text(song.durationText)
            .font(font)
            .foregroundStyle(AppTheme.textSecondary)
            .monospacedDigit()
    }
}

// Animated waveform bars shown when a song is current
private struct WaveformIcon: View {
    @State private var animating = false

    private let heights: [CGFloat] = [0.45, 0.85, 0.60, 0.80, 0.50]
    private let delays: [Double]   = [0.0,  0.15, 0.30, 0.10, 0.25]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.textPrimary)
                    .frame(width: 3, height: animating ? 14 * heights[i] : 4)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(delays[i]),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
