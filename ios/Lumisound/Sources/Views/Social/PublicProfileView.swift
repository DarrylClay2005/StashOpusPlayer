import SwiftUI
import UIKit

// MARK: - PublicProfileView
//
// Read-only view of another user's profile: avatar, bio, their chosen
// main/sub accent colors, pinned favorite tracks, live online/offline +
// now-playing presence, and contextual friend actions (add / accept-decline
// / remove / block) based on the current relationship.
struct PublicProfileView: View {
    let userId: String
    /// Set when this screen is reached via ProfileView's "View as Public"
    /// button — the owner previewing their own public page, not a genuine
    /// visitor. Defaults to `false` so every existing call site
    /// (`PublicProfileView(userId:)`) is unaffected. Suppresses the
    /// friend-request/block controls, which would otherwise render
    /// nonsensically self-referential ("Add Friend" pointed at yourself).
    var isSelfPreview: Bool = false

    @EnvironmentObject private var social: SocialService
    @EnvironmentObject private var account: AccountService
    @StateObject private var presenceService = PresenceService()

    @State private var profile: PublicSocialProfile? = nil
    @State private var presence: SocialPresence? = nil
    @State private var bannerImage: UIImage? = nil
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
            if profile != nil {
                ProfileAccentBackgroundGlow(mainAccent: mainAccentColor, subAccent: subAccentColor)
            }

            if isLoading {
                ProgressView().tint(AppTheme.dynamicAccent)
            } else if let profile {
                ScrollView {
                    VStack(spacing: 16) {
                        if isSelfPreview {
                            Label("This is how your profile looks to others", systemImage: "eye")
                                .font(AppTheme.bodyFont(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ProfileHeaderCard(
                            mainAccent: mainAccentColor,
                            subAccent: subAccentColor,
                            displayName: profile.displayName ?? profile.username,
                            username: profile.username,
                            isOnline: presence?.online ?? false,
                            bannerImage: bannerImage
                        ) {
                            SocialAvatarView(userId: userId, size: 84, fallbackFill: .clear)
                        } action: {
                            if !isSelfPreview {
                                friendActionControl
                            }
                        }

                        if presence?.online == true, presence?.isPlaying == true,
                           let title = presence?.nowPlayingTitle {
                            ProfileInfoCard(title: "Listening To", icon: "waveform", tint: mainAccentColor) {
                                NowPlayingActivityRow(title: title, artist: presence?.nowPlayingArtist, tint: mainAccentColor)
                            }
                        }

                        if let bio = profile.bio, !bio.isEmpty {
                            ProfileInfoCard(title: "Bio / Status", icon: "text.quote", tint: mainAccentColor) {
                                Text(bio)
                                    .font(AppTheme.bodyFont(size: 14))
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }

                        ProfileInfoCard(title: "Member Since", icon: "calendar", tint: subAccentColor) {
                            MemberSinceRow(memberSince: profile.memberSince)
                        }

                        if !profile.pinnedTracks.isEmpty {
                            ProfileInfoCard(title: "Pinned Favorite Tracks", icon: "pin.fill", tint: subAccentColor) {
                                VStack(spacing: 10) {
                                    ForEach(Array(profile.pinnedTracks.enumerated()), id: \.offset) { index, track in
                                        PinnedTrackRow(title: track.title, artist: track.artist, tint: subAccentColor)
                                        if index < profile.pinnedTracks.count - 1 {
                                            Divider().background(AppTheme.textSecondary.opacity(0.15))
                                        }
                                    }
                                }
                            }
                        }

                        if profile.isFriend, !isSelfPreview {
                            ProfileInfoCard(tint: AppTheme.error) {
                                Button(role: .destructive) { showBlockConfirm = true } label: {
                                    Label("Block User", systemImage: "hand.raised.fill")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 40)
                }
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
        bannerImage = await SocialService.loadBanner(userId: userId)
    }
}
