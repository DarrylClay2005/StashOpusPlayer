import SwiftUI

// MARK: - SubscriptionsView
//
// Lets the user follow YouTube/SoundCloud channels (GET/POST/DELETE
// /user/subscriptions). "Check Now" re-resolves a channel's latest uploads
// and surfaces any new tracks, also creating an in-app notification.

struct SubscriptionsView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var subscriptions: [ArtistSubscription] = []
    @State private var isLoading = false

    @State private var channelURL = ""
    @State private var channelName = ""
    @State private var isAdding = false
    @State private var errorText: String?

    @State private var checkingID: String?
    @State private var isCheckingAll = false
    @State private var newTracksBySubscription: [String: [StreamTrack]] = [:]
    @State private var loadingTrackID: String?

    // Tracked playlists (local, on-device) — a separate area from channel follows.
    @ObservedObject private var trackedStore = TrackedPlaylistStore.shared
    @State private var playlistURL = ""
    @State private var playlistName = ""
    @State private var playlistError: String?

    var body: some View {
        List {
            Section {
                TextField("Channel URL, @handle, or name", text: $channelURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .foregroundStyle(AppTheme.textPrimary)

                TextField("Name (optional)", text: $channelName)
                    .autocorrectionDisabled()
                    .foregroundStyle(AppTheme.textPrimary)

                Button {
                    addSubscription()
                } label: {
                    if isAdding {
                        ProgressView()
                    } else {
                        Text("Subscribe")
                    }
                }
                .disabled(isAdding || channelURL.trimmingCharacters(in: .whitespaces).isEmpty)
                .foregroundStyle(AppTheme.dynamicAccent)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.error)
                }
            } header: {
                sectionHeader("Follow a Channel")
            } footer: {
                Text("Enter a YouTube channel URL, @handle, or channel name. Lumisound checks followed channels for new uploads in the background (timing depends on iOS) and notifies you when they appear — or tap \"Check All\" below any time.")
            }
            .listRowBackground(AppTheme.surface)

            if isLoading && subscriptions.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if subscriptions.isEmpty {
                EmptyStateView(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "No subscriptions",
                    message: "Follow a YouTube or SoundCloud channel above to get notified about new uploads."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(subscriptions) { sub in
                    Section {
                        HStack {
                            channelThumbnail(for: sub)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.channelName ?? sub.channelUrl)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Text(sub.channelUrl)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if checkingID == sub.id {
                                ProgressView()
                            } else {
                                Button("Check") {
                                    check(sub)
                                }
                                .font(.footnote)
                                .foregroundStyle(AppTheme.dynamicAccent)
                            }
                        }

                        if let newTracks = newTracksBySubscription[sub.id] {
                            if newTracks.isEmpty {
                                Text("No new uploads.")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            } else {
                                ForEach(newTracks) { track in
                                    Button {
                                        play(track: track)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "play.circle")
                                                .foregroundStyle(AppTheme.dynamicAccent)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(track.title)
                                                    .foregroundStyle(AppTheme.textPrimary)
                                                    .lineLimit(1)
                                                Text(track.artist)
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.textSecondary)
                                            }
                                            Spacer()
                                            if loadingTrackID == track.id {
                                                ProgressView()
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listRowBackground(AppTheme.surface.opacity(0.5))
                    .swipeActions {
                        Button(role: .destructive) {
                            remove(sub)
                        } label: {
                            Label("Unsubscribe", systemImage: "trash")
                        }
                    }
                }
            }

            playlistSections
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !subscriptions.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        checkAll()
                    } label: {
                        if isCheckingAll {
                            ProgressView()
                        } else {
                            Text("Check All")
                        }
                    }
                    .disabled(isCheckingAll || checkingID != nil)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        subscriptions = await account.fetchSubscriptions()
        isLoading = false
    }

    private func addSubscription() {
        let trimmedURL = channelURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty else { return }
        let trimmedName = channelName.trimmingCharacters(in: .whitespaces)
        isAdding = true
        errorText = nil
        Task {
            if await account.addSubscription(channelUrl: trimmedURL, channelName: trimmedName.isEmpty ? nil : trimmedName) {
                channelURL = ""
                channelName = ""
                await load()
            } else {
                errorText = account.errorMessage ?? "Failed to add subscription."
            }
            isAdding = false
        }
    }

    private func remove(_ sub: ArtistSubscription) {
        Task {
            if await account.removeSubscription(id: sub.id) {
                subscriptions.removeAll { $0.id == sub.id }
                newTracksBySubscription[sub.id] = nil
            }
        }
    }

    private func check(_ sub: ArtistSubscription) {
        checkingID = sub.id
        Task {
            newTracksBySubscription[sub.id] = await account.checkSubscription(id: sub.id)
            checkingID = nil
        }
    }

    /// Checks every subscription in turn, same as tapping "Check" on each
    /// row — this is the manual, foreground equivalent of what
    /// `BackgroundRefreshService` runs periodically in the background.
    private func checkAll() {
        guard !isCheckingAll else { return }
        isCheckingAll = true
        Task {
            for sub in subscriptions {
                newTracksBySubscription[sub.id] = await account.checkSubscription(id: sub.id)
            }
            isCheckingAll = false
        }
    }

    private func play(track: StreamTrack) {
        guard loadingTrackID == nil else { return }
        loadingTrackID = track.id
        Task {
            defer { loadingTrackID = nil }
            do {
                let url = try await streaming.streamURL(for: track)
                let song = streaming.toSong(track: track, streamURL: url)
                player.play(song: song, in: [song])
            } catch {
                streaming.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Tracked Playlists

    @ViewBuilder
    private var playlistSections: some View {
        Section {
            TextField("YouTube playlist URL", text: $playlistURL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .foregroundStyle(AppTheme.textPrimary)

            TextField("Name (optional)", text: $playlistName)
                .autocorrectionDisabled()
                .foregroundStyle(AppTheme.textPrimary)

            Button {
                addPlaylist()
            } label: {
                Text("Track Playlist")
            }
            .disabled(playlistURL.trimmingCharacters(in: .whitespaces).isEmpty)
            .foregroundStyle(AppTheme.dynamicAccent)

            if let playlistError {
                Text(playlistError)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.error)
            }
        } header: {
            sectionHeader("Track a Playlist")
        } footer: {
            Text("Paste a YouTube playlist link to track it. Open a tracked playlist to download individual tracks — anything already in your library is detected and skipped so nothing downloads twice.")
        }
        .listRowBackground(AppTheme.surface)

        if !trackedStore.playlists.isEmpty {
            Section {
                ForEach(trackedStore.playlists) { pl in
                    NavigationLink {
                        TrackedPlaylistDetailView(playlist: pl)
                    } label: {
                        HStack(spacing: 12) {
                            playlistThumbnail(for: pl)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Text(pl.lastTrackCount > 0 ? "\(pl.lastTrackCount) tracks" : pl.url)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            trackedStore.remove(id: pl.id)
                        } label: {
                            Label("Untrack", systemImage: "trash")
                        }
                    }
                }
            } header: {
                sectionHeader("Tracked Playlists")
            }
            .listRowBackground(AppTheme.surface.opacity(0.5))
        }
    }

    @ViewBuilder
    private func playlistThumbnail(for pl: TrackedPlaylist) -> some View {
        if let url = URL(string: pl.thumbnailURL), !pl.thumbnailURL.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Image(systemName: "music.note.list")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "music.note.list")
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 40, height: 40)
        }
    }

    private func addPlaylist() {
        let url = playlistURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        playlistError = nil
        if trackedStore.add(url: url, name: playlistName) {
            playlistURL = ""
            playlistName = ""
        } else {
            playlistError = "That playlist is already tracked (or the URL is invalid)."
        }
    }

    @ViewBuilder
    private func channelThumbnail(for sub: ArtistSubscription) -> some View {
        if let thumb = sub.channelThumbnail, let url = URL(string: thumb), !thumb.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 36, height: 36)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }
}
