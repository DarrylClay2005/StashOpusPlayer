import SwiftUI
import UIKit

// MARK: - PresenceIndicatorView
//
// Small reusable online/offline dot + optional "now playing" caption, shared
// by FriendsListView (one per row) and PublicProfileView (one, larger, under
// the name). Purely a display component — it doesn't poll anything itself;
// callers own a `PresenceService` and pass in the latest `SocialPresence`
// they already fetched via the batched friends-presence endpoint.
struct PresenceIndicatorView: View {
    let presence: SocialPresence?
    var showNowPlaying: Bool = true
    var dotSize: CGFloat = 9

    private var isOnline: Bool { presence?.online ?? false }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? AppTheme.success : AppTheme.textSecondary.opacity(0.4))
                .frame(width: dotSize, height: dotSize)
                .overlay(
                    Circle().stroke(AppTheme.background, lineWidth: 1.5)
                )

            if showNowPlaying, isOnline, let title = presence?.nowPlayingTitle {
                HStack(spacing: 4) {
                    if presence?.isPlaying == true {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
                    Text(presenceCaption(title: title, artist: presence?.nowPlayingArtist))
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Text(isOnline ? "Online" : "Offline")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private func presenceCaption(title: String, artist: String?) -> String {
        guard let artist, !artist.isEmpty else { return title }
        return "\(title) — \(artist)"
    }
}

// MARK: - SocialAvatarView
//
// Fetches and displays another user's avatar from GET /user/avatar/{id}
// (public — no auth required, same as the endpoint AccountService+Avatar.swift
// already uses for the signed-in user's own avatar). Always renders through
// `AnimatedImageView` rather than a plain SwiftUI `Image`, so a friend/profile
// with a GIF avatar actually plays here too — every avatar surface the Social
// Ecosystem feature added (friends list, requests, suggestions, public
// profile) reuses this one component instead of each hand-rolling the same
// fetch-and-sniff logic.
struct SocialAvatarView: View {
    let userId: String
    var size: CGFloat = 40
    /// Background shown behind the fallback person icon when there's no
    /// avatar. Pass `.clear` when the caller already draws its own
    /// background (e.g. PublicProfileView's accent-color gradient ring)
    /// so this doesn't paint over it with a flat surface color.
    var fallbackFill: Color = AppTheme.surface

    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            if let image {
                AnimatedImageView(image: image, contentMode: .scaleAspectFill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(fallbackFill)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.45))
                            .foregroundStyle(AppTheme.textSecondary)
                    )
            }
        }
        .task(id: userId) {
            image = await Self.loadAvatar(userId: userId)
        }
    }

    static func loadAvatar(userId: String) async -> UIImage? {
        guard let account = AccountService.shared,
              let req = account.makeBaseRequest("/user/avatar/\(userId)", method: "GET") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        if isGIFData(data) { return UIImage.gifImage(data: data) }
        return UIImage(data: data)
    }
}
