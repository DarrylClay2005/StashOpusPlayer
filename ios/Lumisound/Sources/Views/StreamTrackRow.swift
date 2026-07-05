import SwiftUI
import UniformTypeIdentifiers

// MARK: - StreamTrackRow

struct StreamTrackRow: View {

    let track: StreamTrack
    let isLoading: Bool
    let isDownloading: Bool
    let isDownloaded: Bool
    let onPlay: () -> Void
    let onAddToQueue: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail with a small source-icon badge in the corner — gives each
            // row an at-a-glance platform indicator even outside its grouped section.
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: track.thumbnailURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Image(systemName: sourceIcon)
                            .font(.system(size: 22))
                            .foregroundStyle(AppTheme.textSecondary)
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(width: 56, height: 56)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .clipped()

                Image(systemName: sourceIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(sourceTint, in: Circle())
                    .overlay(Circle().stroke(AppTheme.surface, lineWidth: 1.5))
                    .offset(x: 4, y: 4)
            }

            // Title + artist
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(AppTheme.bodyFont(size: 14).weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(track.artist.isEmpty ? sourceLabelForTrack : track.artist)
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Duration
            Text(track.durationText)
                .font(AppTheme.monoFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 36, alignment: .trailing)

            // Play / spinner
            if isLoading {
                ProgressView()
                    .tint(AppTheme.dynamicAccent)
                    .frame(width: 32, height: 32)
            } else {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.dynamicAccent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            // Download button
            Button(action: onDownload) {
                if isDownloading {
                    ProgressView()
                        .tint(AppTheme.dynamicAccent)
                        .frame(width: 32, height: 32)
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.success)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || isDownloaded)

            // Queue button
            Button(action: onAddToQueue) {
                Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }

    private var sourceIcon: String {
        switch track.source {
        case "soundcloud": return "cloud.fill"
        case "bandcamp":   return "music.note.list"
        default:           return "play.rectangle.fill"
        }
    }

    private var sourceTint: Color {
        switch track.source {
        case "soundcloud": return Color.orange
        case "bandcamp":   return Color.cyan
        default:           return Color.red
        }
    }

    private var sourceLabelForTrack: String {
        switch track.source {
        case "soundcloud": return "SoundCloud"
        case "bandcamp":   return "Bandcamp"
        default:           return "YouTube"
        }
    }
}
