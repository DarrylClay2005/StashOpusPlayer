import PhotosUI
import SwiftUI
import UIKit

// MARK: - ProfileView
//
// The signed-in user's own public-profile editor: avatar, bio, two-tone
// accent customization (main/sub), up to 5 pinned favorite tracks, and the
// "share now playing with friends" privacy toggle that gates presence's
// now-playing line and the friends activity feed (see PresenceService /
// SocialService and the /api/social/* endpoints on the bridge).
struct ProfileView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var social: SocialService
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var draftBio: String = ""
    @State private var mainAccentHex: String? = nil
    @State private var subAccentHex: String? = nil
    @State private var shareNowPlaying: Bool = true
    @State private var memberSince: String? = nil
    @State private var pinnedTracks: [PinnedTrack] = []
    @State private var isSaving = false
    @State private var editingSlot: Int? = nil // which pinned-track slot the picker sheet is editing
    @State private var photosPickerItem: PhotosPickerItem? = nil
    @State private var isUploadingAvatar = false
    @State private var bannerImage: UIImage? = nil
    @State private var bannerPickerItem: PhotosPickerItem? = nil
    @State private var isUploadingBanner = false
    @State private var showAvatarGifPicker = false
    @State private var showBannerGifPicker = false

    private var mainAccentColor: Color { SocialAccentPalette.color(for: mainAccentHex) ?? AppTheme.dynamicAccent }
    private var subAccentColor: Color { SocialAccentPalette.color(for: subAccentHex) ?? AppTheme.accentSoft }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: Header — banner + avatar mirrors how this profile
                    // renders to others, using the user's own chosen
                    // main/sub accent colors.
                    ProfileHeaderCard(
                        mainAccent: mainAccentColor,
                        subAccent: subAccentColor,
                        displayName: account.currentUser?.displayName ?? account.currentUser?.username ?? "",
                        username: account.currentUser?.username ?? "",
                        isOnline: true,
                        bannerImage: bannerImage
                    ) {
                        ZStack {
                            if let img = account.avatarImage {
                                AnimatedImageView(image: img, contentMode: .scaleAspectFill)
                            } else {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [mainAccentColor, subAccentColor],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Text(initials)
                                            .font(.title.bold())
                                            .foregroundStyle(.white)
                                    )
                            }
                            if isUploadingAvatar {
                                Color.black.opacity(0.45)
                                ProgressView().tint(.white)
                            }
                        }
                    } action: {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                PhotosPicker(selection: $photosPickerItem, matching: .images, photoLibrary: .shared()) {
                                    HStack {
                                        Image(systemName: "photo.badge.plus")
                                        Text("Gallery")
                                            .font(AppTheme.bodyFont(size: 13))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(mainAccentColor)
                                    .adaptiveGlass(
                                        tint: mainAccentColor.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        fallback: AppTheme.surface
                                    )
                                }
                                .onChange(of: photosPickerItem) { item in
                                    guard let item else { return }
                                    isUploadingAvatar = true
                                    Task {
                                        defer { isUploadingAvatar = false }
                                        if let data = try? await item.loadTransferable(type: Data.self) {
                                            await account.uploadAvatarData(data)
                                        }
                                        photosPickerItem = nil
                                    }
                                }

                                Button {
                                    showAvatarGifPicker = true
                                } label: {
                                    HStack {
                                        Image(systemName: "party.popper")
                                        Text("Search GIFs")
                                            .font(AppTheme.bodyFont(size: 13))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(mainAccentColor)
                                    .adaptiveGlass(
                                        tint: mainAccentColor.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        fallback: AppTheme.surface
                                    )
                                }
                            }

                            HStack(spacing: 8) {
                                PhotosPicker(selection: $bannerPickerItem, matching: .images, photoLibrary: .shared()) {
                                    HStack {
                                        if isUploadingBanner {
                                            ProgressView().tint(subAccentColor)
                                        } else {
                                            Image(systemName: "photo.on.rectangle.angled")
                                        }
                                        Text("Banner")
                                            .font(AppTheme.bodyFont(size: 13))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(subAccentColor)
                                    .adaptiveGlass(
                                        tint: subAccentColor.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        fallback: AppTheme.surface
                                    )
                                }
                                .disabled(isUploadingBanner)
                                .onChange(of: bannerPickerItem) { item in
                                    guard let item else { return }
                                    isUploadingBanner = true
                                    Task {
                                        defer { isUploadingBanner = false }
                                        if let data = try? await item.loadTransferable(type: Data.self) {
                                            await social.uploadBannerData(data)
                                            // Optimistic local update, same
                                            // reasoning as avatar upload —
                                            // don't make the user wait on a
                                            // round-trip fetch to see their
                                            // own change take effect.
                                            if data.isEmpty == false {
                                                bannerImage = isGIFData(data) ? await UIImage.gifImageAsync(data: data) : UIImage(data: data)
                                            }
                                        }
                                        bannerPickerItem = nil
                                    }
                                }

                                Button {
                                    showBannerGifPicker = true
                                } label: {
                                    HStack {
                                        Image(systemName: "party.popper")
                                        Text("Search GIFs")
                                            .font(AppTheme.bodyFont(size: 13))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(subAccentColor)
                                    .adaptiveGlass(
                                        tint: subAccentColor.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        fallback: AppTheme.surface
                                    )
                                }
                                .disabled(isUploadingBanner)

                                if bannerImage != nil {
                                    Button {
                                        Task {
                                            await social.removeBanner()
                                            bannerImage = nil
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .padding(10)
                                            .adaptiveGlass(
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                                fallback: AppTheme.surface
                                            )
                                    }
                                }
                            }
                        }
                    }

                    // MARK: Now Playing — live local playback state, not a
                    // fetch (this is the owner's own device).
                    if let song = player.currentSong, player.isPlaying {
                        ProfileInfoCard(title: "Listening To", icon: "waveform", tint: mainAccentColor) {
                            NowPlayingActivityRow(
                                title: song.title, artist: song.artist.isEmpty ? nil : song.artist,
                                tint: mainAccentColor, song: song
                            )
                        }
                    }

                    // MARK: Bio
                    ProfileInfoCard(title: "Bio / Status", icon: "text.quote", tint: mainAccentColor) {
                        TextField("Add a short bio or status…", text: $draftBio, axis: .vertical)
                            .lineLimit(3...6)
                            .foregroundStyle(AppTheme.textPrimary)
                            .onChange(of: draftBio) { newValue in
                                if newValue.count > 280 { draftBio = String(newValue.prefix(280)) }
                            }
                        HStack {
                            Spacer()
                            Text("\(draftBio.count)/280")
                                .font(AppTheme.monoFont(size: 11))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    // MARK: Member Since
                    ProfileInfoCard(title: "Member Since", icon: "calendar", tint: subAccentColor) {
                        MemberSinceRow(memberSince: memberSince)
                    }

                    // MARK: Accent colors — Discord-style two-tone
                    ProfileInfoCard(title: "Profile Colors", icon: "paintpalette.fill", tint: mainAccentColor) {
                        AccentColorPickerView(title: "Main Accent", selectedHex: $mainAccentHex)
                            .padding(.vertical, 6)
                        AccentColorPickerView(title: "Sub Accent", selectedHex: $subAccentHex)
                            .padding(.vertical, 6)
                        Text("Main drives your profile's primary chrome; Sub drives secondary highlights — shown to anyone who visits your profile.")
                            .font(AppTheme.bodyFont(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    // MARK: Pinned favorite tracks
                    ProfileInfoCard(title: "Pinned Favorite Tracks", icon: "pin.fill", tint: subAccentColor) {
                        VStack(spacing: 10) {
                            ForEach(0..<5, id: \.self) { slot in
                                Button {
                                    editingSlot = slot
                                } label: {
                                    HStack {
                                        if slot < pinnedTracks.count {
                                            PinnedTrackRow(
                                                title: pinnedTracks[slot].title,
                                                artist: pinnedTracks[slot].artist,
                                                tint: subAccentColor
                                            )
                                        } else {
                                            HStack {
                                                Image(systemName: "pin.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.4))
                                                Text("Empty slot")
                                                    .font(AppTheme.bodyFont(size: 14))
                                                    .foregroundStyle(AppTheme.textSecondary)
                                                Spacer()
                                            }
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                                if slot < 4 {
                                    Divider().background(AppTheme.textSecondary.opacity(0.15))
                                }
                            }
                        }
                        Text("Pick up to 5 tracks to feature on your public profile.")
                            .font(AppTheme.bodyFont(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 4)
                    }

                    // MARK: Privacy — now-playing sharing hook for presence
                    ProfileInfoCard(title: "Presence Privacy", icon: "eye.slash", tint: mainAccentColor) {
                        Toggle(isOn: $shareNowPlaying) {
                            Label("Share Now Playing with Friends", systemImage: "waveform")
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .tint(mainAccentColor)
                        .onChange(of: shareNowPlaying) { newValue in
                            Task { await social.updateProfile(shareNowPlaying: newValue) }
                        }
                        Text("When off, friends only see that you're online — not what you're currently playing. This also hides you from the Friends Activity feed.")
                            .font(AppTheme.bodyFont(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    if let err = social.errorMessage {
                        ProfileInfoCard(tint: AppTheme.error) {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.error)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    saveProfile()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save").bold()
                    }
                }
                .disabled(isSaving)
            }
        }
        .task {
            await social.fetchMyProfile()
            applyLoadedProfile()
        }
        .task {
            guard let userId = account.currentUser?.id else { return }
            bannerImage = await SocialService.loadBanner(userId: userId)
        }
        .sheet(item: Binding(
            get: { editingSlot.map { PinnedSlot(index: $0) } },
            set: { editingSlot = $0?.index }
        )) { slot in
            PinnedTrackPickerSheet(
                currentTrack: slot.index < pinnedTracks.count ? pinnedTracks[slot.index] : nil,
                onPick: { track in
                    setPinnedSlot(slot.index, track: track)
                },
                onRemove: slot.index < pinnedTracks.count ? {
                    removePinnedSlot(slot.index)
                } : nil
            )
            .environmentObject(library)
        }
        .sheet(isPresented: $showAvatarGifPicker) {
            GifPickerSheet { data in
                Task { await account.uploadAvatarData(data) }
            }
        }
        .sheet(isPresented: $showBannerGifPicker) {
            // Matches ProfileHeaderCard's banner aspect closely enough for a
            // crop guide — it doesn't need to be pixel-exact to the current
            // device width, since the banner is still `.scaleAspectFill`ed
            // at display time either way; this just gives the user a
            // reasonable frame to compose within instead of none at all.
            GifPickerSheet(cropAspect: 2.8, isCircularGuide: false) { data in
                Task {
                    await social.uploadBannerData(data)
                    bannerImage = await UIImage.gifImageAsync(data: data)
                }
            }
        }
    }

    private struct PinnedSlot: Identifiable { let index: Int; var id: Int { index } }

    private var initials: String {
        let name = account.currentUser?.displayName ?? account.currentUser?.username ?? "?"
        return String(name.prefix(1)).uppercased()
    }

    private func applyLoadedProfile() {
        guard let profile = social.myProfile else { return }
        draftBio = profile.bio ?? ""
        mainAccentHex = profile.mainAccentHex
        subAccentHex = profile.subAccentHex
        shareNowPlaying = profile.shareNowPlaying
        memberSince = profile.memberSince
        pinnedTracks = profile.pinnedTracks
    }

    private func setPinnedSlot(_ slot: Int, track: PinnedTrack) {
        while pinnedTracks.count <= slot {
            pinnedTracks.append(track)
        }
        pinnedTracks[slot] = track
        Task { await social.setPinnedTracks(pinnedTracks) }
    }

    private func removePinnedSlot(_ slot: Int) {
        guard slot < pinnedTracks.count else { return }
        pinnedTracks.remove(at: slot)
        Task { await social.setPinnedTracks(pinnedTracks) }
    }

    private func saveProfile() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            let trimmed = draftBio.trimmingCharacters(in: .whitespacesAndNewlines)
            await social.updateProfile(
                bio: trimmed,
                mainAccentHex: mainAccentHex,
                subAccentHex: subAccentHex,
                shareNowPlaying: shareNowPlaying
            )
            // Re-sync local @State from whatever the server actually persisted
            // (updateProfile() already refetches into social.myProfile) rather
            // than trusting the optimistic local edit — otherwise a save that
            // silently fails/partially applies leaves the screen showing a
            // value that was never actually stored, and re-entering this
            // screen later would look like "the change didn't take" with no
            // indication why.
            applyLoadedProfile()
        }
    }
}

// MARK: - PinnedTrackPickerSheet

/// Simple searchable picker over the on-device library, used to fill one of
/// the 5 pinned-track slots. Deliberately picks from `library.allSongs`
/// (what's actually on this device) rather than requiring a server-side
/// track search — a pinned track is just a display card on the profile, not
/// something that needs to be streamable from someone else's device.
private struct PinnedTrackPickerSheet: View {
    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss

    let currentTrack: PinnedTrack?
    let onPick: (PinnedTrack) -> Void
    let onRemove: (() -> Void)?

    @State private var query = ""

    private var filteredSongs: [Song] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return library.allSongs }
        let q = query.lowercased()
        return library.allSongs.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let onRemove {
                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Label("Remove Pinned Track", systemImage: "pin.slash")
                    }
                }
                ForEach(filteredSongs.prefix(200)) { song in
                    Button {
                        onPick(PinnedTrack(
                            sourceTrackID: song.sourceTrackID,
                            trackURL: song.url?.absoluteString,
                            title: song.title,
                            artist: song.artist.isEmpty ? nil : song.artist,
                            album: song.album.isEmpty ? nil : song.album
                        ))
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title).foregroundStyle(AppTheme.textPrimary)
                            if !song.artist.isEmpty {
                                Text(song.artist)
                                    .font(AppTheme.bodyFont(size: 12))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search your library")
            .navigationTitle("Pin a Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
