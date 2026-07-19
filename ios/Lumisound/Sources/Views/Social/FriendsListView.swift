import SwiftUI

// MARK: - FriendsListView
//
// The main Friends hub: search/add by username, pending-requests entry
// (badge), mutual-friend suggestions (extra feature #2), the friends list
// itself with live presence, a friends-only activity feed entry (extra
// feature #1), and blocked-users management.
//
// Owns the standing "poll my friends' presence" timer for as long as this
// screen is visible — PresenceService.startFriendsPolling/stopFriendsPolling
// is intentionally screen-scoped (not app-wide) since there's no reason to
// keep refreshing friends' online status when no friends UI is on screen.
struct FriendsListView: View {
    @EnvironmentObject private var social: SocialService
    @EnvironmentObject private var account: AccountService
    @StateObject private var presenceService = PresenceService()

    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var showBlockedUsers = false
    @State private var sendingRequestTo: Set<String> = []
    /// Debounces so every keystroke doesn't fire its own network request —
    /// `SocialService.searchUsers` itself now guards against the resulting
    /// out-of-order completions (see its own doc comment), but there's no
    /// reason to actually make a dozen requests while someone is still
    /// typing a username.
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        List {
            // MARK: Add friend
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("Search by username", text: $searchQuery)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(AppTheme.textPrimary)
                        .onChange(of: searchQuery) { newValue in
                            searchTask?.cancel()
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                guard !Task.isCancelled else { return }
                                isSearching = true
                                await social.searchUsers(query: newValue)
                                isSearching = false
                            }
                        }
                    if isSearching {
                        ProgressView().tint(AppTheme.dynamicAccent)
                    }
                }

                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    if social.searchResults.isEmpty && !isSearching {
                        Text("No users found.")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(social.searchResults) { user in
                            HStack(spacing: 12) {
                                NavigationLink(destination: PublicProfileView(userId: user.userId)) {
                                    userRow(user)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                if sendingRequestTo.contains(user.userId) {
                                    ProgressView().tint(AppTheme.dynamicAccent)
                                } else if isAlreadyFriend(user.userId) {
                                    Text("Friends").font(AppTheme.bodyFont(size: 12)).foregroundStyle(AppTheme.textSecondary)
                                } else if isPendingOutgoing(user.userId) {
                                    Text("Requested").font(AppTheme.bodyFont(size: 12)).foregroundStyle(AppTheme.textSecondary)
                                } else {
                                    Button {
                                        sendRequest(to: user.userId)
                                    } label: {
                                        Image(systemName: "person.badge.plus")
                                            .foregroundStyle(AppTheme.dynamicAccent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            } header: {
                sectionHeader("Add Friends")
            }
            .listRowBackground(AppTheme.surface)

            // MARK: Requests entry
            Section {
                NavigationLink(destination: FriendRequestsView()) {
                    HStack {
                        Label("Friend Requests", systemImage: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(AppTheme.textPrimary)
                        if !social.incomingRequests.isEmpty {
                            Spacer()
                            Text("\(social.incomingRequests.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(AppTheme.dynamicAccent, in: Capsule())
                        }
                    }
                }
                NavigationLink(destination: FriendsActivityFeedView()) {
                    Label("Friends Activity", systemImage: "waveform.path.ecg")
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Button {
                    showBlockedUsers = true
                } label: {
                    Label("Blocked Users", systemImage: "hand.raised")
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .listRowBackground(AppTheme.surface)

            // MARK: Suggestions (extra feature)
            if !social.suggestions.isEmpty {
                Section {
                    ForEach(social.suggestions) { suggestion in
                        HStack(spacing: 12) {
                            NavigationLink(destination: PublicProfileView(userId: suggestion.userId)) {
                                HStack(spacing: 12) {
                                    SocialAvatarView(userId: suggestion.userId, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.displayName ?? suggestion.username)
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Text("\(suggestion.mutualFriendCount) mutual friend\(suggestion.mutualFriendCount == 1 ? "" : "s")")
                                            .font(AppTheme.bodyFont(size: 12))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if sendingRequestTo.contains(suggestion.userId) {
                                ProgressView().tint(AppTheme.dynamicAccent)
                            } else {
                                Button {
                                    sendRequest(to: suggestion.userId)
                                } label: {
                                    Image(systemName: "person.badge.plus")
                                        .foregroundStyle(AppTheme.dynamicAccent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    sectionHeader("People You May Know")
                }
                .listRowBackground(AppTheme.surface)
            }

            // MARK: Friends list
            Section {
                if social.friends.isEmpty {
                    Text("No friends yet — search above to send a request.")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(social.friends) { friend in
                        NavigationLink(destination: PublicProfileView(userId: friend.userId)) {
                            HStack(spacing: 12) {
                                SocialAvatarView(userId: friend.userId, size: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(friend.displayName ?? friend.username)
                                        .foregroundStyle(AppTheme.textPrimary)
                                    PresenceIndicatorView(
                                        presence: presenceByUserId[friend.userId],
                                        dotSize: 8
                                    )
                                }
                            }
                        }
                    }
                }
            } header: {
                sectionHeader("Friends (\(social.friends.count))")
            }
            .listRowBackground(AppTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await social.fetchFriends()
            await social.fetchFriendRequests()
        }
        // `.onAppear` (not `.task`, which only ever runs once for this
        // view's lifetime) — Friends is now a persistent tab rather than a
        // freshly-pushed NavigationLink destination, so re-fetching only
        // on first-ever appearance meant the list could go stale (or never
        // load at all if that one fetch was slow/failed) for the rest of
        // the session. Re-firing on every appearance matches the same fix
        // applied to ProfileView and the existing AccountView badge count.
        .onAppear {
            presenceService.startFriendsPolling(account: account)
            Task {
                await social.fetchFriends()
                await social.fetchFriendRequests()
                await social.fetchSuggestions()
            }
        }
        .onDisappear {
            presenceService.stopFriendsPolling()
        }
        .sheet(isPresented: $showBlockedUsers) {
            NavigationStack { BlockedUsersView() }
        }
    }

    /// Precomputed once per render instead of an O(n) `.first { }` scan per
    /// friend row — turns the whole list's presence lookup from O(n²) into
    /// O(n), which matters once a friends list grows past a couple dozen.
    private var presenceByUserId: [String: SocialPresence] {
        Dictionary(presenceService.friendsPresence.map { ($0.userId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func userRow(_ user: SocialUserRef) -> some View {
        HStack(spacing: 12) {
            SocialAvatarView(userId: user.userId, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName ?? user.username)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("@\(user.username)")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func isAlreadyFriend(_ userId: String) -> Bool {
        social.friends.contains { $0.userId == userId }
    }

    private func isPendingOutgoing(_ userId: String) -> Bool {
        social.outgoingRequests.contains { $0.userId == userId }
    }

    private func sendRequest(to userId: String) {
        guard !sendingRequestTo.contains(userId) else { return }
        sendingRequestTo.insert(userId)
        Task {
            defer { sendingRequestTo.remove(userId) }
            _ = await social.sendFriendRequest(toUserId: userId)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }
}

// MARK: - BlockedUsersView

/// Simple management sheet for GET /api/social/block — presented modally
/// from FriendsListView rather than pushed, since it's an infrequent
/// "moderation" surface rather than a primary navigation destination.
struct BlockedUsersView: View {
    @EnvironmentObject private var social: SocialService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if social.blockedUsers.isEmpty {
                Text("You haven't blocked anyone.")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(social.blockedUsers) { user in
                    HStack {
                        SocialAvatarView(userId: user.userId, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? user.username).foregroundStyle(AppTheme.textPrimary)
                            Text("@\(user.username)")
                                .font(AppTheme.bodyFont(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Button("Unblock") {
                            Task { await social.unblockUser(user.userId) }
                        }
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.dynamicAccent)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await social.fetchBlockedUsers() }
    }
}

// MARK: - FriendsActivityFeedView

/// Extra feature #1: a friends-only feed of recent plays/favorites — see
/// GET /api/social/activity/friends. Distinct from the pre-existing global
/// DiscoverView feed (which surfaces ALL opted-in users, not just friends).
struct FriendsActivityFeedView: View {
    @EnvironmentObject private var social: SocialService

    var body: some View {
        List {
            if social.friendsActivity.isEmpty {
                Text("No recent activity from friends yet.")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .listRowBackground(AppTheme.surface)
            } else {
                ForEach(social.friendsActivity) { entry in
                    HStack(spacing: 12) {
                        SocialAvatarView(userId: entry.userId, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(entry.displayName ?? entry.username)
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Image(systemName: entry.isPlayed ? "play.fill" : "heart.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(entry.isPlayed ? AppTheme.dynamicAccent : AppTheme.error)
                            }
                            Text([entry.title, entry.artist].compactMap { $0 }.joined(separator: " — "))
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Friends Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await social.fetchFriendsActivity() }
        .refreshable { await social.fetchFriendsActivity() }
    }
}
