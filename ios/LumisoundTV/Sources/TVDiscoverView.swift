import SwiftUI

// MARK: - TVDiscoverView
//
// Round 3: Discover Mix, On This Day, and server-computed Smart Playlists —
// all bridge-backed (GET /user/discover-mix, /user/on-this-day, /user/music/
// smart-playlists), unlike iOS's on-device Lua smart-playlist engine / mood
// playlist service, which read the local library scan tvOS doesn't have.
// Discover Mix and On This Day both need real play history to have anything
// to show — TVPlayerModel now reports plays via POST /user/history as it
// plays, same as this screen's data ultimately depends on.

struct TVDiscoverView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String

    private var discoverQueue: [TVPlayable] {
        client.discoverMix.compactMap { client.playable(from: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                discoverMixSection
                onThisDaySection
                smartPlaylistsSection
            }
            .padding(.vertical, 50)
        }
        .task {
            if client.discoverMix.isEmpty { await client.fetchDiscoverMix(token: token) }
            if client.onThisDay.isEmpty { await client.fetchOnThisDay(token: token) }
            if client.smartPlaylists.isEmpty { await client.fetchSmartPlaylists(token: token) }
        }
    }

    // MARK: Discover Mix

    private var discoverMixSection: some View {
        sectionShell(title: "Discover Mix", subtitle: "Suggested based on your most-played artists") {
            if client.isLoadingDiscoverMix {
                ProgressView().padding(.horizontal, 60)
            } else if client.discoverMix.isEmpty {
                emptyRow("Keep listening — suggestions show up once you've built some play history.")
            } else {
                horizontalGrid {
                    ForEach(client.discoverMix) { track in
                        NavigationLink(value: TVPlayContext(queue: discoverQueue, startID: track.id)) {
                            TVTrackCard(track: track)
                        }
                        .buttonStyle(.card)
                        .tvSearchTrackActions(client: client, token: token, track: track)
                    }
                }
            }
        }
    }

    // MARK: On This Day

    private var onThisDaySection: some View {
        sectionShell(title: "On This Day", subtitle: "What you were playing on this date in years past") {
            if client.isLoadingOnThisDay {
                ProgressView().padding(.horizontal, 60)
            } else if client.onThisDay.isEmpty {
                emptyRow("Nothing played on this date yet — check back as your history grows.")
            } else {
                VStack(alignment: .leading, spacing: 40) {
                    ForEach(client.onThisDay) { group in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(group.yearsAgo == 1 ? "1 Year Ago" : "\(group.yearsAgo) Years Ago")
                                .font(.title2.weight(.semibold))
                                .padding(.horizontal, 60)
                            horizontalGrid {
                                let queue = group.tracks.compactMap { client.playable(from: $0) }
                                ForEach(group.tracks) { track in
                                    NavigationLink(value: TVPlayContext(queue: queue, startID: track.id)) {
                                        TVTrackCard(track: track)
                                    }
                                    .buttonStyle(.card)
                                    .tvSearchTrackActions(client: client, token: token, track: track)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Smart playlists

    private var smartPlaylistsSection: some View {
        sectionShell(title: "Smart Playlists", subtitle: "Auto-generated from your cloud library's tempo") {
            if client.isLoadingSmartPlaylists {
                ProgressView().padding(.horizontal, 60)
            } else if client.smartPlaylists.allSatisfy({ $0.tracks.isEmpty }) {
                emptyRow("Upload music to your Personal Cloud Library to unlock tempo-based playlists.")
            } else {
                horizontalGrid {
                    ForEach(client.smartPlaylists) { bucket in
                        NavigationLink {
                            TVSmartPlaylistDetailView(client: client, token: token, bucket: bucket)
                        } label: {
                            smartPlaylistCard(bucket)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
        }
    }

    private func smartPlaylistCard(_ bucket: TVSmartPlaylistBucket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: smartPlaylistIcon(bucket.key)).font(.system(size: 50)).foregroundStyle(.secondary)
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(bucket.name).font(.headline)
            Text("\(bucket.tracks.count) \(bucket.tracks.count == 1 ? "song" : "songs")")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(width: 280)
    }

    private func smartPlaylistIcon(_ key: String) -> String {
        switch key {
        case "energetic": return "bolt.fill"
        case "focus": return "brain.head.profile"
        case "chill": return "cloud.fill"
        case "sleep": return "moon.zzz.fill"
        default: return "music.note.list"
        }
    }

    // MARK: Shared layout helpers

    @ViewBuilder
    private func sectionShell<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 34, weight: .bold))
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)
            content()
        }
    }

    @ViewBuilder
    private func horizontalGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 32) { content() }
                .padding(.horizontal, 60)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.title3).foregroundStyle(.secondary)
            .padding(.horizontal, 60)
    }
}

// MARK: - Smart playlist detail

struct TVSmartPlaylistDetailView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String
    let bucket: TVSmartPlaylistBucket

    /// Resolved against the loaded library by filename — see
    /// `TVBridgeClient.resolvedTrack(for:)`. An entry that doesn't resolve
    /// (library not loaded yet, or a genuine mismatch) is dropped rather
    /// than shown unplayable.
    private var resolvedTracks: [UserMusicTrack] {
        bucket.tracks.compactMap { client.resolvedTrack(for: $0) }
    }
    private var queue: [TVPlayable] {
        resolvedTracks.compactMap { client.playable(from: $0, token: token) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(bucket.name).font(.system(size: 40, weight: .bold))
                    Text("\(resolvedTracks.count) \(resolvedTracks.count == 1 ? "song" : "songs")")
                        .font(.title3).foregroundStyle(.secondary)
                    if let first = queue.first {
                        NavigationLink(value: TVPlayContext(queue: queue, startID: first.id)) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.card)
                        .padding(.top, 10)
                    }
                }

                if client.isLoadingLibrary {
                    ProgressView().padding(.top, 20)
                } else if resolvedTracks.isEmpty {
                    Text("No matching songs found in your library.")
                        .font(.title3).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(resolvedTracks) { track in
                            NavigationLink(value: TVPlayContext(queue: queue, startID: track.id)) {
                                HStack(spacing: 24) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title.isEmpty ? track.filename : track.title).font(.title3)
                                        Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                                            .font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(track.durationText).font(.callout).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 14)
                                .padding(.horizontal, 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.card)
                            .tvTrackActions(client: client, token: token, track: track)
                        }
                    }
                }
            }
            .padding(60)
        }
        .task {
            if client.library.isEmpty { await client.fetchLibrary(token: token) }
        }
    }
}
