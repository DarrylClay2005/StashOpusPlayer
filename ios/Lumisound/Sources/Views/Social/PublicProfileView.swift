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
    /// Set when this screen is showing the signed-in user's own profile —
    /// either the Profile tab's default view or ProfileView's "View as
    /// Public" preview sheet. Defaults to `false` so every existing call
    /// site (`PublicProfileView(userId:)`) is unaffected. Suppresses the
    /// friend-request/block controls, which would otherwise render
    /// nonsensically self-referential ("Add Friend" pointed at yourself).
    var isSelfPreview: Bool = false
    /// Non-nil when this view IS the Profile tab's primary destination
    /// (rather than the "View as Public" preview sheet reached from inside
    /// the editor): renders an "Edit Profile" button in the header's action
    /// slot instead of the "this is how you look to others" hint, and is
    /// called when that button is tapped so the caller can push the editor.
    /// Only meaningful when `isSelfPreview` is true.
    var onEditProfile: (() -> Void)? = nil

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

    /// For the self-preview case, "online" is answered locally (are you
    /// logged in and is the app actually in the foreground right now?)
    /// rather than by round-tripping through the same `/api/social/presence`
    /// GET a genuine visitor's client uses. That GET fires the instant this
    /// view appears, racing the heartbeat POST that reports you online in
    /// the first place (PresenceService.startHeartbeat, owned separately by
    /// ContentView) — on a fresh app-open -> Profile tab tap, or after any
    /// single transient network hiccup, the fetch can land before the
    /// server has a fresh row and this screen would show YOU as offline
    /// despite the app being open right in front of you. There's no such
    /// race for the local answer: it's already known without asking anyone.
    private var isOnline: Bool {
        if isSelfPreview {
            return account.isLoggedIn && UIApplication.shared.applicationState == .active
        }
        return presence?.online ?? false
    }

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
                        if isSelfPreview, onEditProfile == nil {
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
                            isOnline: isOnline,
                            bannerImage: bannerImage
                        ) {
                            SocialAvatarView(userId: userId, size: 84, fallbackFill: .clear)
                        } action: {
                            if !isSelfPreview {
                                friendActionControl
                            } else if let onEditProfile {
                                Button(action: onEditProfile) {
                                    Label("Edit Profile", systemImage: "pencil")
                                        .foregroundStyle(mainAccentColor)
                                }
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
            // Friend-request state only feeds `friendActionControl`, which is
            // never rendered in self-preview (see its `!isSelfPreview` guard
            // above) — fetching it there is a pure wasted round trip on the
            // single most-hit screen in the app (the Profile tab).
            if !isSelfPreview {
                await social.fetchFriendRequests()
            }
        }
        // Lightweight self-cancelling poll for this one profile's presence —
        // stops automatically when the view disappears, unlike the standing
        // friends-list timer in PresenceService (which only runs while
        // FriendsListView itself is on screen). Skipped for self-preview:
        // `isOnline` above answers itself locally and never reads `presence`.
        .task {
            guard !isSelfPreview else { return }
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
        // Both are independent GETs — fire them concurrently instead of back
        // to back. Gate the screen only on the profile fetch (the essential
        // data); the banner is decorative and pops in via `bannerImage`'s
        // own `@State` update whenever it lands, same as any other async
        // image in this app.
        async let bannerTask = SocialService.loadBanner(userId: userId)
        profile = await social.fetchPublicProfile(userId: userId)
        isLoading = false
        bannerImage = await bannerTask
    }
}
