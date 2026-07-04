import SwiftUI

// MARK: - Shape type erasure (artwork clip shape needs to return one of 3 shapes)

private struct AnyLibraryShape: Shape {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { pathBuilder = shape.path(in:) }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

// MARK: - CustomLibraryRowView
//
// Generic renderer for user-created custom library row styles. Unlike the
// 4 built-in `SongCardStyle` cases (each a hand-written body in `SongRow`),
// this one interprets a `CustomLibraryRowStyle` value at runtime.
struct CustomLibraryRowView: View {
    let song: Song
    let isCurrent: Bool
    let config: CustomLibraryRowStyle
    var subtitle: String? = nil

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    private var resolvedSubtitle: String {
        subtitle ?? "\(song.artistName) · \(song.albumName)"
    }

    private var titleColor: Color {
        isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary
    }

    private var artworkShape: AnyLibraryShape {
        switch config.artworkShape {
        case .square:
            return AnyLibraryShape(Rectangle())
        case .rounded:
            return AnyLibraryShape(RoundedRectangle(cornerRadius: config.artworkCornerRadius, style: .continuous))
        case .circle:
            return AnyLibraryShape(Circle())
        }
    }

    var body: some View {
        layoutBody
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.25), value: isCurrent)
            .contextMenu {
                SongContextMenuContent(song: song)
                    .environmentObject(library)
                    .environmentObject(player)
            }
    }

    @ViewBuilder
    private var layoutBody: some View {
        switch config.layout {
        case .row:
            flatRowBody
        case .card:
            cardRowBody
        }
    }

    private var flatRowBody: some View {
        VStack(spacing: 0) {
            mainRow
                .padding(.vertical, config.density.verticalPadding)
            if config.showDivider {
                Divider().opacity(0.3)
            }
        }
        .background { backgroundTint }
        .overlay(alignment: .leading) { borderAccent }
    }

    private var cardRowBody: some View {
        mainRow
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBackgroundFill)
            }
            .overlay {
                if isCurrent && config.accentUsage == .border {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppTheme.dynamicAccent.opacity(0.5), lineWidth: 1.5)
                }
            }
            .padding(.vertical, 4)
    }

    private var mainRow: some View {
        HStack(spacing: config.density.spacing) {
            artworkView
            textStack
            Spacer(minLength: 0)
            if config.showDuration { durationLabel }
        }
    }

    private var artworkView: some View {
        let size = CGFloat(config.artworkSize)
        return ArtworkThumbnail(song: song, size: size)
            .clipShape(artworkShape)
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(song.displayName)
                .foregroundStyle(titleColor)
                .font(.body)
                .fontWeight(config.titleWeight.fontWeight)
                .lineLimit(1)
            if config.showSubtitle {
                Text(resolvedSubtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var durationLabel: some View {
        Text(song.durationText)
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var backgroundTint: some View {
        if isCurrent && config.accentUsage == .backgroundTint {
            AppTheme.dynamicAccent.opacity(0.12)
        }
    }

    @ViewBuilder
    private var borderAccent: some View {
        if isCurrent && config.accentUsage == .border {
            Rectangle().fill(AppTheme.dynamicAccent).frame(width: 3)
        }
    }

    private var cardBackgroundFill: Color {
        isCurrent && config.accentUsage == .backgroundTint
            ? AppTheme.dynamicAccent.opacity(0.16)
            : AppTheme.elevatedSurface.opacity(0.6)
    }
}

// MARK: - CustomLibraryGridCellView
//
// Grid-cell counterpart, mirroring `SongGridCell`'s layout but driven by the
// same `CustomLibraryRowStyle` config used for the row form.
struct CustomLibraryGridCellView: View {
    let song: Song
    let isCurrent: Bool
    let config: CustomLibraryRowStyle
    var subtitle: String? = nil
    var trackNumber: Int? = nil

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    private var resolvedSubtitle: String {
        subtitle ?? song.artistName
    }

    private var cellCornerRadius: CGFloat {
        switch config.artworkShape {
        case .square:  return 0
        case .rounded: return CGFloat(config.artworkCornerRadius)
        case .circle:  return 999
        }
    }

    private var cellBackgroundFill: Color {
        isCurrent && config.accentUsage == .backgroundTint
            ? AppTheme.dynamicAccent.opacity(0.16)
            : AppTheme.surface.opacity(0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ArtworkThumbnail(song: song, size: geo.size.width)
                    .overlay(alignment: .bottomTrailing) { nowPlayingBadge }
                    .overlay(alignment: .topLeading) { trackNumberBadge }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayName)
                    .font(.caption)
                    .fontWeight(config.titleWeight.fontWeight)
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .lineLimit(2)
                if config.showSubtitle {
                    Text(resolvedSubtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cellBackgroundFill)
        }
        .overlay {
            if isCurrent && config.accentUsage == .border {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.dynamicAccent.opacity(0.5), lineWidth: 1.5)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
        .contextMenu {
            SongContextMenuContent(song: song)
                .environmentObject(library)
                .environmentObject(player)
        }
    }

    @ViewBuilder
    private var nowPlayingBadge: some View {
        if isCurrent {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(AppTheme.dynamicAccent, in: Circle())
                .padding(4)
        }
    }

    @ViewBuilder
    private var trackNumberBadge: some View {
        if let trackNumber, trackNumber > 0 {
            Text("\(trackNumber)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(4)
        }
    }
}
