import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var account: AccountService
    @State private var editMode: EditMode = .inactive
    @State private var isRestoringQueue = false

    private var totalDuration: TimeInterval {
        player.queue.reduce(0) { $0 + $1.duration }
    }

    private func formatDurationLong(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0m" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else if m > 0 {
            return "\(m)m \(s)s"
        } else {
            return "\(s)s"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GalleryBackgroundView().ignoresSafeArea()
                queueList
            }
            .navigationTitle("Queue")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    // Shuffle toggle
                    Button {
                        player.toggleShuffle()
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(player.shuffleEnabled ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                            .fontWeight(player.shuffleEnabled ? .bold : .regular)
                    }
                    // Repeat cycle button
                    Button {
                        player.cycleRepeatMode()
                    } label: {
                        Image(systemName: repeatIcon)
                            .foregroundStyle(player.repeatMode != .off ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                            .fontWeight(player.repeatMode != .off ? .bold : .regular)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if account.isLoggedIn {
                        Button {
                            restoreQueueFromCloud()
                        } label: {
                            if isRestoringQueue {
                                ProgressView()
                            } else {
                                Image(systemName: "icloud.and.arrow.down")
                                    .foregroundStyle(AppTheme.dynamicAccent)
                            }
                        }
                        .disabled(isRestoringQueue)
                    }
                    if !player.queue.isEmpty {
                        Button {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        } label: {
                            Text(editMode == .active ? "Done" : "Edit")
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }

                        Button(role: .destructive) {
                            clearQueue()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(AppTheme.error)
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .safeAreaInset(edge: .bottom) {
                MiniPlayerBar()
            }
        }
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var queueList: some View {
        List {
            if player.queue.isEmpty {
                emptyState
            } else {
                queueItems
                queueFooter
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Queue is empty")
                .font(.headline)
                .foregroundStyle(AppTheme.textSecondary)
            Text("Start playing a song to add it to the queue.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var queueItems: some View {
        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, song in
            Button {
                player.setQueue(player.queue, startIndex: index, autoplay: true)
            } label: {
                queueRowContent(index: index, song: song)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                index == player.currentIndex
                    ? AppTheme.dynamicAccent.opacity(0.12)
                    : Color.clear
            )
            .listRowSeparatorTint(AppTheme.surface)
        }
        .onMove { source, destination in
            player.moveQueueItem(from: source, to: destination)
        }
        .onDelete { offsets in
            player.removeFromQueue(at: offsets)
        }
    }

    private func queueRowContent(index: Int, song: Song) -> some View {
        HStack(spacing: 12) {
            // Index or "Now Playing" badge
            ZStack {
                if index == player.currentIndex {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 52, height: 22)
                    Text("Playing")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 52, alignment: .leading)
                }
            }
            .frame(width: 52, height: 22, alignment: .leading)

            SongRow(song: song, isCurrent: index == player.currentIndex)
        }
        .padding(.vertical, 2)
    }

    private var queueFooter: some View {
        HStack {
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text("\(player.queue.count) track\(player.queue.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Text("·")
                .foregroundStyle(AppTheme.textSecondary)
                .font(.caption)

            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(formatDurationLong(totalDuration))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Replaces the current queue with the one saved on the server (synced
    /// from another device), keeping playback paused on whatever is now first.
    private func restoreQueueFromCloud() {
        guard !isRestoringQueue else { return }
        isRestoringQueue = true
        Task {
            let songs = await account.fetchQueue(library: library)
            if !songs.isEmpty {
                player.setQueue(songs, startIndex: 0, autoplay: false)
            }
            isRestoringQueue = false
        }
    }

    private func clearQueue() {
        // Remove all items from the queue
        let allIndices = IndexSet(player.queue.indices)
        if !allIndices.isEmpty {
            player.removeFromQueue(at: allIndices)
            ToastCenter.shared.show("Queue cleared", category: .info, icon: "trash")
        }
        editMode = .inactive
    }
}
