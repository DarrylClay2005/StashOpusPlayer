import Foundation
import SwiftUI

/// The full-screen Queue editor.
///
/// Reworked around a real distinction between "Manually Queued" tracks
/// (explicit "Play Next"/"Add to Queue" actions — see `QueueSource`) and the
/// "Up Next" auto-continuation tail (the loaded playlist/album/library list,
/// or Auto-Radio's picks) — rather than one flat, undifferentiated list.
/// Drag-reorder (via the trailing handle, in Edit mode — the same mechanism
/// already used by `PlaylistDetailView`) and swipe-to-remove (available at
/// all times, no Edit mode needed) both operate within their own section, so
/// reordering a manually-queued track can never accidentally spill into the
/// auto-continuation tail or vice versa.
struct QueueView: View {
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var account: AccountService
    @State private var editMode: EditMode = .inactive
    @State private var isRestoringQueue = false
    @State private var showSaveQueueAlert = false
    @State private var saveQueueName = ""
    @State private var nowPlayingPulse = false

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
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    // Shuffle toggle
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            player.toggleShuffle()
                        }
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(player.shuffleEnabled ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                            .fontWeight(player.shuffleEnabled ? .bold : .regular)
                            .scaleEffect(player.shuffleEnabled ? 1.1 : 1.0)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: player.shuffleEnabled)
                    // Repeat cycle button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            player.cycleRepeatMode()
                        }
                    } label: {
                        Image(systemName: repeatIcon)
                            .foregroundStyle(player.repeatMode != .off ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                            .fontWeight(player.repeatMode != .off ? .bold : .regular)
                            .contentTransition(.opacity)
                            .scaleEffect(player.repeatMode != .off ? 1.1 : 1.0)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: player.repeatMode)
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
            .alert("Save Queue as Playlist", isPresented: $showSaveQueueAlert) {
                TextField("Playlist name", text: $saveQueueName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveQueueAsPlaylist() }
            } message: {
                Text("Creates a new playlist from all \(player.queue.count) track\(player.queue.count == 1 ? "" : "s") currently in the queue.")
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

    // MARK: - Section data

    /// Songs before the current one — shown de-emphasized; tap to jump back,
    /// swipe to remove, but not reorderable (history isn't "up next").
    private var earlierSongs: [Song] {
        guard player.currentIndex > 0, player.currentIndex <= player.queue.count else { return [] }
        return Array(player.queue.prefix(player.currentIndex))
    }

    /// The contiguous auto-continuation tail after the manually-queued block —
    /// exactly the range `AudioPlayerManager.moveAutoQueueItem` reorders, so
    /// local `.onMove` indices from this exact array always land in range.
    private var autoTailSongs: [Song] {
        guard player.repeatMode != .one, !player.queue.isEmpty else { return [] }
        let start = player.manualBlockRange().upperBound
        guard start <= player.queue.count else { return [] }
        return Array(player.queue[start...])
    }

    /// When Repeat All wraps back to the start of the queue, these are the
    /// songs that play after the tail loops — shown read-only in their own
    /// small section (deliberately NOT merged into `autoTailSongs`, which
    /// would desync `.onMove`'s local indices from what
    /// `moveAutoQueueItem` actually reorders).
    private var autoWrapSongs: [Song] {
        guard player.repeatMode == .all, player.currentIndex > 0 else { return [] }
        return Array(player.queue[0..<min(player.currentIndex, player.queue.count)])
    }

    // MARK: - List

    private var queueList: some View {
        List {
            if player.queue.isEmpty {
                emptyState
            } else {
                contextHeaderSection
                earlierSection
                nowPlayingSection
                manualSection
                autoTailSection
                autoWrapSection
                queueFooter
            }
        }
        // Without an explicit style this defaults to a grouped-card look
        // (gaps between rows showing the gallery background through) — the
        // same "split into disconnected pieces" bug fixed in FavoritesView
        // et al., just via the implicit default instead of an explicit
        // `.insetGrouped`.
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        // Centralizes "smooth animated insertion/removal" for every queue
        // mutation (add/remove/reorder/skip) behind one implicit animation
        // keyed to the queue's identity order, instead of needing every
        // single call site to remember to wrap itself in `withAnimation`.
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: player.queue.map(\.id))
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

    /// Persistent "Playing from X" label + pill "Save" affordance — saves the
    /// current queue's contents as a new playlist via the library's existing
    /// `createPlaylist(name:songIDs:)`.
    private var contextHeaderSection: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.playingFromContextLabel(library: library))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(player.queue.count) track\(player.queue.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Button {
                saveQueueName = defaultQueueName()
                showSaveQueueAlert = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.dynamicAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.dynamicAccent.opacity(0.15), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var earlierSection: some View {
        if !earlierSongs.isEmpty {
            Section {
                ForEach(earlierSongs, id: \.id) { song in
                    queueRow(song: song, leadingIcon: nil)
                        .opacity(0.55)
                }
            } header: {
                Text("Earlier")
            }
            .listRowSeparatorTint(AppTheme.surface)
        }
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        if let current = player.currentSong {
            Section {
                SongRow(song: current, isCurrent: true)
                    .padding(.vertical, 2)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.dynamicAccent.opacity(nowPlayingPulse ? 0.20 : 0.09))
                    )
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                            nowPlayingPulse = true
                        }
                    }
            } header: {
                Text("Now Playing")
            }
            .listRowSeparatorTint(AppTheme.surface)
        }
    }

    @ViewBuilder
    private var manualSection: some View {
        let manual = player.manuallyQueuedUpNext
        if !manual.isEmpty {
            Section {
                ForEach(manual, id: \.id) { song in
                    queueRow(song: song, leadingIcon: "person.fill")
                }
                .onMove { source, destination in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        player.moveManualQueueItem(from: source, to: destination)
                    }
                }
            } header: {
                Label("Manually Queued", systemImage: "person.fill.badge.plus")
            }
            .listRowSeparatorTint(AppTheme.surface)
        }
    }

    @ViewBuilder
    private var autoTailSection: some View {
        let auto = autoTailSongs
        if !auto.isEmpty {
            Section {
                ForEach(auto, id: \.id) { song in
                    queueRow(song: song, leadingIcon: nil)
                }
                .onMove { source, destination in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        player.moveAutoQueueItem(from: source, to: destination)
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Up Next")
                    if player.shuffleEnabled {
                        Image(systemName: "shuffle")
                    }
                }
            }
            .listRowSeparatorTint(AppTheme.surface)
        }
    }

    @ViewBuilder
    private var autoWrapSection: some View {
        if !autoWrapSongs.isEmpty {
            Section {
                ForEach(autoWrapSongs, id: \.id) { song in
                    queueRow(song: song, leadingIcon: nil)
                        .opacity(0.7)
                }
            } header: {
                Label("Then, From the Top", systemImage: "repeat")
            }
            .listRowSeparatorTint(AppTheme.surface)
        }
    }

    /// A single reorderable/removable row shared by every section — tap to
    /// jump to that position in the queue (preserving playback context),
    /// swipe (at any time, no Edit mode needed) to remove.
    private func queueRow(song: Song, leadingIcon: String?) -> some View {
        Button {
            jumpTo(song: song)
        } label: {
            HStack(spacing: 8) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.dynamicAccent)
                        .frame(width: 14)
                }
                SongRow(song: song, isCurrent: false)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    player.removeSong(id: song.id)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        ))
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

    // MARK: - Actions

    /// Jumps to a different index within the SAME already-loaded queue —
    /// preserve whatever playlist context it came from (this used to always
    /// clear it, wiping the Now Playing theme memory just by tapping a
    /// different row in Queue).
    private func jumpTo(song: Song) {
        guard let index = player.queue.firstIndex(where: { $0.id == song.id }) else { return }
        player.setQueue(player.queue, startIndex: index, autoplay: true, playlistID: player.currentPlaylistID)
    }

    private func defaultQueueName() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Queue – \(formatter.string(from: Date()))"
    }

    private func saveQueueAsPlaylist() {
        let name = saveQueueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !player.queue.isEmpty else { return }
        _ = library.createPlaylist(name: name, songIDs: player.queue.map(\.id))
        ToastCenter.shared.show("Saved \"\(name)\"", category: .success, icon: "checkmark.circle.fill")
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
            withAnimation(.easeInOut(duration: 0.25)) {
                player.removeFromQueue(at: allIndices)
            }
            ToastCenter.shared.show("Queue cleared", category: .info, icon: "trash")
        }
        editMode = .inactive
    }
}
