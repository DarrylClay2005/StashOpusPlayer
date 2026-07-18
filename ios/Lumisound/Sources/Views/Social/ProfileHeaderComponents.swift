import SwiftUI

// MARK: - Profile header components
//
// Shared building blocks for ProfileView (own, editable) and
// PublicProfileView (another user's, read-only) — a Discord-style banner
// with an overlapping avatar/status dot, plus a small family of "info card"
// sections (Bio, Now Playing, Member Since, Pinned Tracks) tinted with the
// profile owner's own main/sub accent colors so a profile actually looks
// like *theirs*, not a generic template.

// MARK: - ProfileHeaderCard

/// Gradient banner (the user's main → sub accent) with the avatar overlapping
/// its bottom edge, an optional online/offline status dot, and the
/// display name/username underneath. `action` is whatever goes right below
/// (an "Edit Profile"-style control for the owner, a friend-request control
/// for a public profile) — kept as a trailing slot rather than baked in here
/// since the two screens' actions are genuinely different shapes.
struct ProfileHeaderCard<Avatar: View, Action: View>: View {
    let mainAccent: Color
    let subAccent: Color
    let displayName: String
    let username: String
    /// `nil` hides the status dot entirely (own-profile editor doesn't need
    /// to tell you whether you're online).
    let isOnline: Bool?

    private let avatar: Avatar
    private let action: Action

    init(
        mainAccent: Color,
        subAccent: Color,
        displayName: String,
        username: String,
        isOnline: Bool?,
        @ViewBuilder avatar: () -> Avatar,
        @ViewBuilder action: () -> Action
    ) {
        self.mainAccent = mainAccent
        self.subAccent = subAccent
        self.displayName = displayName
        self.username = username
        self.isOnline = isOnline
        self.avatar = avatar()
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(
                colors: [mainAccent, subAccent],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                // A soft bottom fade so a light avatar-ring stroke and the
                // name text underneath both stay legible against any accent
                // pair, including light ones like White/Amber.
                LinearGradient(colors: [.clear, .black.opacity(0.32)], startPoint: .top, endPoint: .bottom)
            )
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            // `.overlay` composites on top WITHOUT being clipped by the
            // banner's own clipShape above — this is what lets the avatar
            // hang half below the banner's rounded rect instead of being
            // cut off at its edge.
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomTrailing) {
                    avatar
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.background, lineWidth: 4))
                        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 3)
                    if let isOnline {
                        Circle()
                            .fill(isOnline ? AppTheme.success : AppTheme.textSecondary.opacity(0.5))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(AppTheme.background, lineWidth: 3))
                    }
                }
                .padding(.leading, 16)
                .offset(y: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("@\(username)")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.leading, 32)
            .padding(.top, 48)
            .padding(.trailing, 16)

            action
                .padding(.horizontal, 16)
                .padding(.top, 14)
        }
    }
}

// MARK: - ProfileInfoCard

/// A single titled "section card" — Bio, Now Playing, Member Since, Pinned
/// Tracks, Presence Privacy all render as one of these, tinted with the
/// profile's own accent so every section reads as part of the same profile
/// rather than a plain system list. Uses the same `adaptiveGlass` material
/// the rest of the redesigned app already uses for floating chrome.
struct ProfileInfoCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    let tint: Color
    private let content: Content

    init(title: String? = nil, icon: String? = nil, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                    Text(title.uppercased())
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .kerning(0.8)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(
            tint: tint.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            fallback: AppTheme.surface
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - NowPlayingActivityRow

/// "Listening to Lumisound" row — reused by both the owner's live
/// `player.currentSong` and a friend's fetched `SocialPresence`, so the same
/// visual shows up whether the data came from local playback state or a
/// network fetch.
struct NowPlayingActivityRow: View {
    let title: String
    let artist: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.2))
                Image(systemName: "music.note")
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if let artist, !artist.isEmpty {
                    Text(artist)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "waveform")
                .font(.caption)
                .foregroundStyle(tint)
        }
    }
}

// MARK: - MemberSinceRow

/// "Member Since" row — formats the ISO8601 `member_since` timestamp the
/// bridge derives from `ios_users.created_at` (account creation, not the
/// lazily-created social-profile row) into a long localized date.
struct MemberSinceRow: View {
    let memberSince: String?

    private var formatted: String {
        guard let memberSince, let date = sharedISO8601Formatter.date(from: memberSince) else {
            return "Unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(AppTheme.textSecondary)
            Text(formatted)
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

// MARK: - PinnedTrackRow

/// One pinned-track row inside a Pinned Tracks `ProfileInfoCard` — shared
/// look between the owner's editable slot list and a public profile's
/// read-only list (the owner's version wraps this in a `Button`/adds a
/// chevron at the call site rather than duplicating the row layout).
struct PinnedTrackRow: View {
    let title: String
    let artist: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .font(.caption)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if let artist, !artist.isEmpty {
                    Text(artist)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
}
