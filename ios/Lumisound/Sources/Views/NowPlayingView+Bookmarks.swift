import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Bookmarks

    var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                addBookmarkAtCurrentPosition()
            } label: {
                // `player.position` (a plain computed passthrough to
                // `player.progress.position`, not `@Published` itself) rather
                // than the `progress` environment object directly — this is
                // just a one-shot read for display text, and NowPlayingView
                // no longer declares `progress` as an `@EnvironmentObject`
                // (see NowPlayingView+Timeline.swift's isolation comment).
                Label("Add Bookmark at \(formattedBookmarkTime(player.position))", systemImage: "bookmark.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.dynamicAccent)
            }
            .disabled(player.currentSong == nil)

            if bookmarksForCurrentSong.isEmpty {
                Text("No bookmarks on this track yet.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(bookmarksForCurrentSong) { bookmark in
                    bookmarkRow(bookmark)
                }
            }
        }
        .padding(.vertical, 4)
        .panelStyle()
    }

    var bookmarksForCurrentSong: [TrackBookmark] {
        guard let songID = player.currentSong?.id else { return [] }
        return BookmarkStore.shared.bookmarks(for: songID)
    }

    func bookmarkRow(_ bookmark: TrackBookmark) -> some View {
        HStack {
            Button {
                player.seek(to: bookmark.timestamp)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(AppTheme.dynamicAccent)
                    Text(bookmark.label)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(formattedBookmarkTime(bookmark.timestamp))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Button {
                voiceMemoBookmark = bookmark
            } label: {
                Image(systemName: VoiceMemoStore.shared.hasMemo(for: bookmark.id) ? "waveform.circle.fill" : "mic.circle")
                    .foregroundStyle(AppTheme.dynamicAccent.opacity(0.85))
            }
            .buttonStyle(.plain)

            Button {
                guard let songID = player.currentSong?.id else { return }
                BookmarkStore.shared.removeBookmark(songID: songID, bookmarkID: bookmark.id)
                VoiceMemoStore.shared.deleteMemo(for: bookmark.id)
                bookmarksRefreshToken = UUID()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
            }
        }
    }

    func addBookmarkAtCurrentPosition() {
        guard let songID = player.currentSong?.id else { return }
        BookmarkStore.shared.addBookmark(
            songID: songID,
            timestamp: player.position,
            label: "Bookmark at \(formattedBookmarkTime(player.position))"
        )
        bookmarksRefreshToken = UUID()
    }

    func formattedBookmarkTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
