import PhotosUI
import SwiftUI

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

    @State private var draftBio: String = ""
    @State private var mainAccentHex: String? = nil
    @State private var subAccentHex: String? = nil
    @State private var shareNowPlaying: Bool = true
    @State private var pinnedTracks: [PinnedTrack] = []
    @State private var isSaving = false
    @State private var editingSlot: Int? = nil // which pinned-track slot the picker sheet is editing
    @State private var photosPickerItem: PhotosPickerItem? = nil
    @State private var isUploadingAvatar = false

    private var mainAccentColor: Color { SocialAccentPalette.color(for: mainAccentHex) ?? AppTheme.dynamicAccent }
    private var subAccentColor: Color { SocialAccentPalette.color(for: subAccentHex) ?? AppTheme.accentSoft }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            List {
                // MARK: Header — mirrors how this profile renders to others,
                // using the user's own chosen main/sub accent colors.
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [mainAccentColor, subAccentColor],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 88, height: 88)

                            if let img = account.avatarImage {
                                AnimatedImageView(image: img, contentMode: .scaleAspectFill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                Text(initials)
                                    .font(.largeTitle.bold())
                                    .foregroundStyle(.white)
                            }

                            if isUploadingAvatar {
                                Circle().fill(.black.opacity(0.45)).frame(width: 88, height: 88)
                                ProgressView().tint(.white)
                            }
                        }
                        .shadow(color: mainAccentColor.opacity(0.4), radius: 10, x: 0, y: 4)

                        PhotosPicker(selection: $photosPickerItem, matching: .images, photoLibrary: .shared()) {
                            Text("Change Avatar (GIF supported)")
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(mainAccentColor)
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

                        Text(account.currentUser?.displayName ?? account.currentUser?.username ?? "")
                            .font(.title3.bold())
                            .foregroundStyle(mainAccentColor)
                        if let username = account.currentUser?.username {
                            Text("@\(username)")
                                .font(AppTheme.bodyFont(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Bio
                Section {
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
                } header: {
                    sectionHeader("Bio / Status")
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Accent colors — Discord-style two-tone
                Section {
                    AccentColorPickerView(title: "Main Accent", selectedHex: $mainAccentHex)
                        .padding(.vertical, 6)
                    AccentColorPickerView(title: "Sub Accent", selectedHex: $subAccentHex)
                        .padding(.vertical, 6)
                } header: {
                    sectionHeader("Profile Colors")
                } footer: {
                    Text("Main drives your profile's primary chrome; Sub drives secondary highlights — shown to anyone who visits your profile.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Pinned favorite tracks
                Section {
                    ForEach(0..<5, id: \.self) { slot in
                        Button {
                            editingSlot = slot
                        } label: {
                            HStack {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(slot < pinnedTracks.count ? subAccentColor : AppTheme.textSecondary.opacity(0.4))
                                if slot < pinnedTracks.count {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pinnedTracks[slot].title)
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        if let artist = pinnedTracks[slot].artist, !artist.isEmpty {
                                            Text(artist)
                                                .font(AppTheme.bodyFont(size: 12))
                                                .foregroundStyle(AppTheme.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                } else {
                                    Text("Empty slot")
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                } header: {
                    sectionHeader("Pinned Favorite Tracks")
                } footer: {
                    Text("Pick up to 5 tracks to feature on your public profile.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                // MARK: Privacy — now-playing sharing hook for presence
                Section {
                    Toggle(isOn: $shareNowPlaying) {
                        Label("Share Now Playing with Friends", systemImage: "waveform")
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .tint(mainAccentColor)
                    .onChange(of: shareNowPlaying) { newValue in
                        Task { await social.updateProfile(shareNowPlaying: newValue) }
                    }
                } header: {
                    sectionHeader("Presence Privacy")
                } footer: {
                    Text("When off, friends only see that you're online — not what you're currently playing. This also hides you from the Friends Activity feed.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)

                if let err = social.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.error)
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
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
