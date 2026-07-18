import SwiftUI

// MARK: - PublicProfileView
//
// Read-only view of another user's profile: avatar, bio, their chosen
// main/sub accent colors, pinned favorite tracks, live online/offline +
// now-playing presence, and contextual friend actions (add / accept-decline
// / remove / block) based on the current relationship.
struct PublicProfileView: View {
    let userId: String

    @EnvironmentObject private var social: SocialService
    @EnvironmentObject private var account: AccountService
    @StateObject private var presenceService = PresenceService()

    @State private var profile: PublicSocialProfile? = nil
    @State private var presence: SocialPresence? = nil
    @State private var isLoading = true
    @State private var isActing = false
    @State private var showBlockConfirm = false
    @State private var showRemoveConfirm = false

    private var mainAccentColor: Color { SocialAccentPalette.color(for: profile?.mainAccentHex) ?? AppTheme.dynamicAccent }
    private var subAccentColor: Color { SocialAccentPalette.color(for: profile?.subAccentHex) ?? AppTheme.accentSoft }

    /// An incoming pending request FROM this user, if any.
    private var incomingRequest: SocialFriendRequest? {
        social.incomingRequests.first { $0.userId == userId }
    }
    /// An outgoing pending request TO this user, if any.
    private var outgoingRequest: SocialFriendRequest? {
        social.outgoingRequests.first { $0.userId == userId }
    }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(AppTheme.dynamicAccent)
            } else if let profile {
                List {
                    Section {
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [mainAccentColor, subAccentColor],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 84, height: 84)
                                SocialAvatarView(userId: userId, size: 78, fallbackFill: .clear)
                            }
                            .shadow(color: mainAccentColor.opacity(0.4), radius: 8, x: 0, y: 4)

                            Text(profile.displayName ?? profile.username)
                                .font(.title3.bold())
                                .foregroundStyle(mainAccentColor)
                            Text("@\(profile.username)")
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)

                            PresenceIndicatorView(presence: presence)
                                .padding(.top, 2)

                            if let bio = profile.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(AppTheme.bodyFont(size: 14))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 6)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(AppTheme.surface)

                    Section {
                        friendActionControl
                    }
                    .listRowBackground(AppTheme.surface)

                    if !profile.pinnedTracks.isEmpty {
                        Section {
                            ForEach(Array(profile.pinnedTracks.enumerated()), id: \.offset) { _, track in
                                HStack {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(subAccentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title).foregroundStyle(AppTheme.textPrimary)
                                        if let artist = track.artist, !artist.isEmpty {
                                            Text(artist)
                                                .font(AppTheme.bodyFont(size: 12))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            sectionHeader("Pinned Favorite Tracks")
                        }
                        .listRowBackground(AppTheme.surface)
                    }

                    if profile.isFriend {
                        Section {
                            Button(role: .destructive) { showBlockConfirm = true } label: {
                                Label("Block User", systemImage: "hand.raised.fill")
                            }
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                Text("This profile isn't available.")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .navigationTitle(profile?.displayName ?? profile?.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
            await social.fetchFriendRequests()
        }
        // Lightweight self-cancelling poll for this one profile's presence —
        // stops automatically when the view disappears, unlike the standing
        // friends-list timer in PresenceService (which only runs while
        // FriendsListView itself is on screen).
        .task {
            while !Task.isCancelled {
                presence = await presenceService.fetchPresence(userId: userId, account: account)
                try? await Task.sleep(nanoseconds: UInt64(PresenceService.friendsPollInterval * 1_000_000_000))
            }
        }
        .confirmationDialog("Block this user?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task {
                    await social.blockUser(userId)
                    await loadProfile()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll no longer see each other's profiles, and any friendship or pending request will be removed.")
        }
        .confirmationDialog("Remove this friend?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove Friend", role: .destructive) {
                Task {
                    await social.removeFriend(userId)
                    await loadProfile()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var friendActionControl: some View {
        if isActing {
            HStack { Spacer(); ProgressView().tint(AppTheme.dynamicAccent); Spacer() }
        } else if let profile, profile.isFriend {
            Button(role: .destructive) { showRemoveConfirm = true } label: {
                Label("Remove Friend", systemImage: "person.fill.badge.minus")
            }
        } else if let incoming = incomingRequest {
            HStack {
                Button {
                    act { await social.acceptRequest(incoming.id) }
                } label: {
                    Label("Accept Request", systemImage: "person.fill.checkmark")
                        .foregroundStyle(AppTheme.success)
                }
                Spacer()
                Button {
                    act { await social.declineRequest(incoming.id) }
                } label: {
                    Label("Decline", systemImage: "xmark")
                        .foregroundStyle(AppTheme.error)
                }
            }
        } else if let outgoing = outgoingRequest {
            Button {
                act { await social.cancelRequest(outgoing.id) }
            } label: {
                Label("Cancel Request", systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(AppTheme.textSecondary)
            }
        } else {
            Button {
                act { _ = await social.sendFriendRequest(toUserId: userId) }
            } label: {
                Label("Add Friend", systemImage: "person.badge.plus")
                    .foregroundStyle(AppTheme.dynamicAccent)
            }
        }
    }

    private func act(_ operation: @escaping () async -> Void) {
        guard !isActing else { return }
        isActing = true
        Task {
            defer { isActing = false }
            await operation()
        }
    }

    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        profile = await social.fetchPublicProfile(userId: userId)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }
}
