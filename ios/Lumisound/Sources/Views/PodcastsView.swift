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

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if subscriptions.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(subscriptions) { sub in
                        NavigationLink(destination: PodcastEpisodesView(subscription: sub)) {
                            row(for: sub)
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
        }
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

    @State private var feedURLText = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
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
            }
            .navigationTitle("Add Podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Add") { submit() }
                            .disabled(feedURLText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func submit() {
        let url = feedURLText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        isSubmitting = true
        errorText = nil
        Task {
            let result = await account.subscribeToPodcast(feedURL: url)
            isSubmitting = false
            if result != nil {
                await onAdded()
                dismiss()
            } else {
                errorText = account.errorMessage ?? "Couldn't add that feed."
            }
        }
    }
}
