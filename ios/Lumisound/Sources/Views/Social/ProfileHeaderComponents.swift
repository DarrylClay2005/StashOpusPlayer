import SwiftUI
import UIKit

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
    /// A user-uploaded banner image, or `nil` to fall back to the plain
    /// main/sub accent gradient. Rendered through `AnimatedImageView` (not a
    /// plain SwiftUI `Image`) so a GIF banner actually plays.
    var bannerImage: UIImage? = nil
    /// Purely cosmetic ring/glow/etc. layered around the avatar — see
    /// AvatarFrameStyle.swift. Defaults to "none" so every existing call
    /// site is unaffected.
    var avatarFrame: String = "none"
    /// e.g. "she/her" — shown right after the @username, Discord-style.
    var pronouns: String? = nil
    /// A short "what I'm up to" line (emoji + text), independent of the
    /// longer Bio card below — Discord custom-status style.
    var statusEmoji: String? = nil
    var statusText: String? = nil

    private let avatar: Avatar
    private let action: Action

    init(
        mainAccent: Color,
        subAccent: Color,
        displayName: String,
        username: String,
        isOnline: Bool?,
        bannerImage: UIImage? = nil,
        avatarFrame: String = "none",
        pronouns: String? = nil,
        statusEmoji: String? = nil,
        statusText: String? = nil,
        @ViewBuilder avatar: () -> Avatar,
        @ViewBuilder action: () -> Action
    ) {
        self.mainAccent = mainAccent
        self.subAccent = subAccent
        self.displayName = displayName
        self.username = username
        self.isOnline = isOnline
        self.bannerImage = bannerImage
        self.avatarFrame = avatarFrame
        self.pronouns = pronouns
        self.statusEmoji = statusEmoji
        self.statusText = statusText
        self.avatar = avatar()
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let bannerImage {
                    AnimatedImageView(image: bannerImage, contentMode: .scaleAspectFill)
                } else {
                    LinearGradient(
                        colors: [mainAccent, subAccent],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            // `AnimatedImageView` (a `UIViewRepresentable`) has no shape-like
            // "expand to fill proposed space" behavior the way `LinearGradient`
            // does — without this it would size to the banner image's own
            // intrinsic pixel dimensions instead of stretching edge-to-edge.
            .frame(maxWidth: .infinity)
            .overlay(
                // A soft bottom fade so a light avatar-ring stroke and the
                // name text underneath both stay legible against any accent
                // pair or banner image, including busy/light ones.
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
                    AvatarFrameOverlay(style: AvatarFrameStyle.from(avatarFrame), diameter: 84, mainTint: mainAccent, subTint: subAccent)
                    avatar
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        // Was a plain `AppTheme.background`-colored ring —
                        // purely a cutout border with zero connection to the
                        // profile's own chosen accent. Whenever a banner
                        // image is set (the common case, and this user's
                        // case specifically), the banner covers the
                        // main/sub gradient below entirely, so this ring
                        // was the *only* place `mainAccent` could show up
                        // in the header at all — and it wasn't using it.
                        .overlay(Circle().stroke(mainAccent, lineWidth: 4))
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
                HStack(spacing: 6) {
                    Text("@\(username)")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                    if let pronouns, !pronouns.isEmpty {
                        Text("· \(pronouns)")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
                    }
                }
                if let statusText, !statusText.isEmpty {
                    HStack(spacing: 4) {
                        if let statusEmoji, !statusEmoji.isEmpty {
                            Text(statusEmoji)
                        }
                        Text(statusText)
                            .font(AppTheme.bodyFont(size: 12))
                            .foregroundStyle(AppTheme.textPrimary.opacity(0.85))
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
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

// MARK: - ProfileAccentBackgroundGlow

/// A soft ambient wash of the profile's own main/sub accent colors bleeding
/// down from the banner into the rest of the screen — Discord-style "your
/// profile theme color tints the whole page," rather than the screen just
/// staying plain black below the banner regardless of what accent colors
/// were actually chosen. Meant to sit as the base layer of the screen's
/// `ZStack`, behind the scrollable content, on both `ProfileView` (own,
/// editable) and `PublicProfileView` (another user's) so the effect is
/// consistent everywhere a profile is shown.
struct ProfileAccentBackgroundGlow: View {
    let mainAccent: Color
    let subAccent: Color

    var body: some View {
        LinearGradient(
            colors: [
                mainAccent.opacity(0.5),
                subAccent.opacity(0.28),
                subAccent.opacity(0.08),
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: 480)
        // Heavily blurred so this reads as an ambient color wash rather
        // than a hard-edged colored rectangle sitting behind the content —
        // the same "glow" treatment already used for the mini-player's
        // play button shadow and similar accent-colored chrome elsewhere.
        .blur(radius: 60)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
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
    /// The actual `Song` being played, when known — lets this row show real
    /// artwork via `ArtworkThumbnail` instead of a generic note icon. Only
    /// available on the owner's own profile (`player.currentSong`); a
    /// friend's presence is fetched from the bridge as plain title/artist
    /// strings with no artwork reference, so their card still falls back to
    /// the icon.
    var song: Song? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let song {
                ArtworkThumbnail(song: song, size: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.2))
                    Image(systemName: "music.note")
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)
            }

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
        guard let memberSince, let date = parseServerDate(memberSince) else {
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

// MARK: - MusicCompatibilityRow

/// "Music Match" score row — a percentage bar plus a couple of rows of
/// shared-artist/shared-genre chips, backed by GET
/// /api/social/compatibility/{user_id}. Friends-only server-side (see
/// main.py's `social_compatibility`), so this is only ever shown once the
/// viewed profile is confirmed a friend.
struct MusicCompatibilityRow: View {
    let compatibility: MusicCompatibility
    let tint: Color

    var body: some View {
        if compatibility.insufficientData {
            Text("Not enough listening history yet to compute a match.")
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(compatibility.score)%")
                        .font(.title2.bold())
                        .foregroundStyle(tint)
                    Text("match")
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.15))
                        Capsule().fill(tint)
                            .frame(width: geo.size.width * CGFloat(min(max(compatibility.score, 0), 100)) / 100)
                    }
                }
                .frame(height: 8)

                if !compatibility.sharedArtists.isEmpty {
                    CompatibilityChipRow(label: "Shared Artists", items: compatibility.sharedArtists, tint: tint)
                }
                if !compatibility.sharedGenres.isEmpty {
                    CompatibilityChipRow(label: "Shared Genres", items: compatibility.sharedGenres, tint: tint)
                }
            }
        }
    }
}

private struct CompatibilityChipRow: View {
    let label: String
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(AppTheme.bodyFont(size: 9))
                .foregroundStyle(AppTheme.textSecondary)
                .kerning(0.6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(tint.opacity(0.16)))
                    }
                }
            }
        }
    }
}

// MARK: - TopMusicShowcaseRow

/// "Top Genres" / "Top Artists" showcase — an auto-generated snapshot of
/// what someone actually listens to, built from the same
/// `get_user_taste_profile` signal already used for the Music Match score,
/// gated behind the profile's own `show_top_genres` opt-in (see
/// `MusicCompatibilityRow`'s doc comment for why artists/genres are kept as
/// separate chip rows rather than merged into one list).
struct TopMusicShowcaseRow: View {
    let topGenres: [String]
    let topArtists: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !topArtists.isEmpty {
                CompatibilityChipRow(label: "Top Artists", items: topArtists, tint: tint)
            }
            if !topGenres.isEmpty {
                CompatibilityChipRow(label: "Top Genres", items: topGenres, tint: tint)
            }
        }
    }
}

// MARK: - ProfileCommentRow

/// One guestbook message row — author avatar/name, body text, relative
/// timestamp, and (when permitted) a delete button. Deletion is allowed for
/// whoever wrote the comment OR the profile owner moderating their own
/// guestbook, mirroring the bridge's `delete_profile_comment` rule exactly.
struct ProfileCommentRow: View {
    let comment: ProfileComment
    let tint: Color
    let canDelete: Bool
    let onDelete: () -> Void

    private var relativeTime: String {
        guard let date = comment.date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SocialAvatarView(userId: comment.authorUserId, size: 32, fallbackFill: .clear)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.authorDisplayName ?? comment.authorUsername)
                        .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if !relativeTime.isEmpty {
                        Text(relativeTime)
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Text(comment.body)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Spacer(minLength: 0)
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
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
