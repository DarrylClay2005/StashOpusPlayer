import SwiftUI

// MARK: - PodcastsView
//
// Subscription list + add-a-feed form. A subscription is validated by the
// bridge fetching the feed once (see main.py's subscribe_podcast) — this
// screen only shows what's already confirmed to parse.
struct PodcastsView: View {
    @EnvironmentObject private var account: AccountService

    @State private var subscriptions: [PodcastSubscription] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @AppStorage(PodcastAutoDownloadService.enabledKey) private var autoDownloadEnabled = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if subscriptions.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        Toggle("Auto-Download New Episodes", isOn: $autoDownloadEnabled)
                    } footer: {
                        Text("Downloads episodes published in the last 2 days, checked every few hours (up to 3 per show per check).")
                    }
                    ForEach(subscriptions) { sub in
                        NavigationLink(destination: PodcastEpisodesView(subscription: sub)) {
                            row(for: sub)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleMute(sub)
                            } label: {
                                Label(
                                    sub.notificationsMuted ? "Unmute" : "Mute",
                                    systemImage: sub.notificationsMuted ? "bell" : "bell.slash"
                                )
                            }
                            .tint(AppTheme.dynamicAccent)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Podcasts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddPodcastSheet { await reload() }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.square")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.textSecondary)
            Text("No Podcasts Yet")
                .font(.headline)
            Text("Add a show's RSS feed URL to start listening.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Add a Podcast") { showAddSheet = true }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.dynamicAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for sub: PodcastSubscription) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: sub.artworkURL.flatMap(URL.init)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(AppTheme.surface)
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(sub.title?.isEmpty == false ? sub.title! : sub.feedURL)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            if sub.notificationsMuted {
                Spacer()
                Image(systemName: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func toggleMute(_ sub: PodcastSubscription) {
        guard let index = subscriptions.firstIndex(where: { $0.id == sub.id }) else { return }
        let newValue = !sub.notificationsMuted
        subscriptions[index].notificationsMuted = newValue
        Task { await account.setPodcastNotificationsMuted(id: sub.id, muted: newValue) }
    }

    private func reload() async {
        isLoading = true
        subscriptions = await account.fetchPodcastSubscriptions()
        isLoading = false
    }

    private func delete(at offsets: IndexSet) {
        let toRemove = offsets.map { subscriptions[$0] }
        subscriptions.remove(atOffsets: offsets)
        Task {
            for sub in toRemove {
                await account.unsubscribeFromPodcast(id: sub.id)
            }
        }
    }
}

private struct AddPodcastSheet: View {
    @EnvironmentObject private var account: AccountService
    @Environment(\.dismiss) private var dismiss
    let onAdded: () async -> Void

    private enum Mode: String, CaseIterable { case search = "Search", url = "Feed URL" }
    @State private var mode: Mode = .search

    @State private var feedURLText = ""
    @State private var errorText: String?

    @State private var searchQuery = ""
    @State private var searchResults: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var subscribingFeedURL: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if mode == .search {
                    searchBody
                } else {
                    urlBody
                }
            }
            .navigationTitle("Add Podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Search tab

    private var searchBody: some View {
        List {
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
            if isSearching && searchResults.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if searchResults.isEmpty && !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("No podcasts found.")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            ForEach(searchResults) { result in
                Button {
                    subscribe(feedURL: result.feedURL)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.title ?? "Untitled")
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(2)
                            if let artist = result.artist {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        Spacer()
                        if subscribingFeedURL == result.feedURL {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }
                    }
                }
                .disabled(subscribingFeedURL != nil)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchQuery, prompt: "Search podcasts")
        .onChange(of: searchQuery) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await runSearch(newValue)
            }
        }
    }

    private func runSearch(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        searchResults = await account.searchPodcasts(query: query)
        isSearching = false
    }

    private func subscribe(feedURL: String) {
        subscribingFeedURL = feedURL
        errorText = nil
        Task {
            let result = await account.subscribeToPodcast(feedURL: feedURL)
            subscribingFeedURL = nil
            if result != nil {
                await onAdded()
                dismiss()
            } else {
                errorText = account.errorMessage ?? "Couldn't add that feed."
            }
        }
    }

    // MARK: Feed URL tab

    private var urlBody: some View {
        Form {
            Section {
                TextField("https://example.com/feed.xml", text: $feedURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Feed URL")
            } footer: {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            Section {
                if subscribingFeedURL != nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    Button("Add") { subscribe(feedURL: feedURLText.trimmingCharacters(in: .whitespaces)) }
                        .disabled(feedURLText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
