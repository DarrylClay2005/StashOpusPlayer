import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Queue Preview

    /// Mirrors `AudioPlayerManager.resolveNextIndex`'s semantics so "Up Next" only ever
    /// shows songs that will actually play next — previously this always wrapped the
    /// queue regardless of `repeatMode`, so e.g. with Repeat off and the queue near its
    /// end it listed earlier tracks that would never play (playback simply stops at the
    /// end), which is what showed up as "Next Up doesn't update properly at all".
    var upNextSongs: [Song] {
        guard player.queue.count > 1 else { return [] }

        if player.repeatMode == .one {
            // The current song repeats — there's nothing else "up next".
            return []
        }

        // Shuffle reorders `queue` itself (see AudioPlayerManager.shuffleQueue), so the
        // same sequential walk below already reflects the shuffled play order.
        var result: [Song] = []
        var i = player.currentIndex + 1
        while result.count < 10 && i < player.queue.count {
            result.append(player.queue[i])
            i += 1
        }
        if player.repeatMode == .all {
            i = 0
            while result.count < 10 && i < player.currentIndex {
                result.append(player.queue[i])
                i += 1
            }
        }
        return result
    }

    var queuePreviewSection: some View {
        DisclosureGroup(
            isExpanded: $showQueuePreview,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    if upNextSongs.isEmpty {
                        Text("Queue is empty")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(upNextSongs.enumerated()), id: \.element.id) { idx, song in
                                    Button {
                                        if let queueIdx = player.queue.firstIndex(where: { $0.id == song.id }) {
                                            player.setQueue(player.queue, startIndex: queueIdx, autoplay: true)
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            ArtworkThumbnail(song: song, size: 60)
                                                .overlay(
                                                    idx == 0
                                                        ? AnyView(
                                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                                .stroke(AppTheme.dynamicAccent, lineWidth: 2)
                                                          )
                                                        : AnyView(EmptyView())
                                                )
                                            Text(song.displayName)
                                                .font(.caption2)
                                                .foregroundStyle(idx == 0 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                                                .lineLimit(1)
                                                .frame(width: 60)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.top, 10)
                        }
                    }
                }
            },
            label: {
                HStack(spacing: 6) {
                    Text("Up Next")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if !upNextSongs.isEmpty {
                        Text("\(upNextSongs.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.dynamicAccent, in: Capsule())
                    }
                    if player.shuffleEnabled {
                        Image(systemName: "shuffle")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
                    Spacer()
                    Text("\(player.queue.count) tracks")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        )
        .tint(AppTheme.dynamicAccent)
        .panelStyle()
    }
}
