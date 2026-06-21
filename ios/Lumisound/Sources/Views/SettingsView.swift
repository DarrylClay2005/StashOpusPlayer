import MediaPlayer
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    // MARK: Dependencies

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var sleepTimer: SleepTimerService
    @EnvironmentObject private var updater: UpdateService
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var cacheManager: CacheManagerService
    @EnvironmentObject private var folderService: MusicFolderService

    @State private var showLogin = false

    /// Shared with `ContentView`, which hides the floating Car Mode button and
    /// disables auto-activation on car-stereo connection when this is off.
    @AppStorage("carModeEnabled") private var carModeEnabled: Bool = false

    /// When on, downloads ask the bridge to use aria2 (multi-connection) as the
    /// yt-dlp downloader. Default OFF: benchmarking showed the native downloader
    /// is ~2-3x faster than aria2 on YouTube's CDN for this deployment (aria2's
    /// many-connection splitting added overhead instead of bypassing throttling).
    /// Kept as an opt-in for networks where YouTube hard-throttles single
    /// connections, where aria2 can genuinely win. Read by
    /// `StreamingService.downloadToLibrary` and sent as `use_aria2` to the bridge.
    @AppStorage("ytdlp_use_aria2") private var ytdlpUseAria2: Bool = false

    // MARK: YouTube API Key Validation / Exposure Check State

    @State private var youtubeKeyConfig: YoutubeApiKeyConfig?
    @State private var youtubeKeyInput = ""
    @State private var isValidatingYouTubeKey = false
    @State private var isSavingYouTubeKey = false
    @State private var youtubeExposureTimer: Timer?

    /// Once a configured key is rejected for quota, re-show the "Set Key"
    /// field so the user can replace it. Persisted so it survives app
    /// relaunches until a new/working key is saved or validates again.
    @AppStorage("youtube_api_key_quota_exceeded") private var youtubeKeyQuotaExceeded = false

    // MARK: Body

    /// Top-level Settings categories — replaces the old single cluttered
    /// scroll with focused tabs, each showing only its related sections.
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case audio = "Audio"
        case library = "Library"
        case ytdlp = "yt-dlp"
        case app = "App"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "person.crop.circle"
            case .audio:   return "waveform"
            case .library: return "music.note.list"
            case .ytdlp:   return "arrow.down.circle"
            case .app:     return "gearshape"
            }
        }
    }

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker

                List {
                    // Update banner — visible on every tab when an update is available.
                    if updater.updateAvailable {
                        Section {
                            UpdateBannerView()
                                .environmentObject(updater)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    switch selectedTab {
                    case .general:
                        accountSection
                        appearanceSection
                        sleepTimerSection
                    case .audio:
                        playbackAudioSection
                        carModeSection
                    case .library:
                        librarySection
                        streamingDownloadsSection
                    case .ytdlp:
                        ytdlpSection
                    case .app:
                        updatesSection
                        helpSection
                        aboutSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(GalleryBackgroundView().ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(account)
            }
            .task {
                await refreshYouTubeKeyStatus()
                startYouTubeExposureMonitor()
            }
            .onDisappear {
                youtubeExposureTimer?.invalidate()
                youtubeExposureTimer = nil
            }
        }
    }

    /// Horizontal, scrollable category selector pinned under the title.
    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedTab == tab ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedTab == tab ? AppTheme.dynamicAccent : AppTheme.surface.opacity(0.6),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: — Account Section

    private var accountSection: some View {
        Section {
            if account.isLoggedIn, let user = account.currentUser {
                NavigationLink(destination: AccountView()
                    .environmentObject(account)
                    .environmentObject(library)
                ) {
                    HStack(spacing: 12) {
                        // Avatar: real image or initials fallback
                        ZStack {
                            if let img = account.avatarImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.dynamicAccent, AppTheme.accentSoft],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Text(String((user.displayName ?? user.username).prefix(1)).uppercased())
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.3), radius: 4, x: 0, y: 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? user.username)
                                .fontWeight(.medium)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("Tap to manage account")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            } else {
                Button { showLogin = true } label: {
                    Label("Sign In / Create Account", systemImage: "person.badge.plus")
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
            }
        } header: {
            sectionHeader("Account")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Library Section

    private var librarySection: some View {
        Section {
            // Default scan source picker
            Picker(selection: Binding(
                get: { UserDefaults.standard.string(forKey: "default_scan_source") ?? "apple_music" },
                set: { UserDefaults.standard.set($0, forKey: "default_scan_source") }
            )) {
                Text("iPhone Music Library (Apple Music)").tag("apple_music")
                Text("App Files (Transferred via Mac)").tag("app_storage")
                Text("Both").tag("both")
            } label: {
                Label("Scan on Launch", systemImage: "magnifyingglass.circle")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .pickerStyle(.menu)
            .tint(AppTheme.dynamicAccent)

            // Access status row
            HStack {
                Label("Media Library Access", systemImage: "music.note.house")
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(mediaAccessStatusText)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(mediaAccessStatusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(mediaAccessStatusColor.opacity(0.15), in: Capsule())
            }

            // Grant / Scan button
            if MPMediaLibrary.authorizationStatus() != .authorized {
                Button {
                    library.requestAccessAndScan()
                } label: {
                    Label("Grant Access", systemImage: "checkmark.shield")
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
            } else {
                Button {
                    library.scanMediaLibrary()
                } label: {
                    HStack {
                        Label("Scan Library", systemImage: "arrow.clockwise")
                            .foregroundStyle(AppTheme.dynamicAccent)
                        Spacer()
                        if library.isScanning {
                            ProgressView()
                                .tint(AppTheme.dynamicAccent)
                        }
                    }
                }
                .disabled(library.isScanning)
            }

            // Library error message (if any)
            if let error = library.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Stats
            LabeledContent("Songs") {
                Text("\(library.allSongs.count)")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            LabeledContent("Artists") {
                Text("\(library.artists.count)")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            LabeledContent("Albums") {
                Text("\(library.albums.count)")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            LabeledContent("Playlists") {
                Text("\(library.playlists.count)")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            // Corrupt file finder
            NavigationLink(destination: CorruptFilesView()) {
                Label("Corrupt File Finder", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // Duplicate finder
            NavigationLink(destination: DuplicateFilesView()) {
                Label("Duplicate Finder", systemImage: "doc.on.doc")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // Storage & cache manager
            NavigationLink(destination: CacheManagerView().environmentObject(cacheManager)) {
                Label("Storage & Cache", systemImage: "internaldrive")
                    .foregroundStyle(AppTheme.textPrimary)
            }

            // Force metadata sync
            Button {
                Task {
                    await library.forceMetadataSync(using: folderService)
                    // forceMetadataSync runs silently otherwise — without this the
                    // button just shows a brief spinner and nothing else, which is
                    // indistinguishable from doing nothing at all even though it
                    // really did rescan, re-tag, and re-enrich every track.
                    if let result = library.lastScanResult {
                        ToastCenter.shared.show(result, category: .success, icon: "checkmark.circle")
                    }
                }
            } label: {
                HStack {
                    Label("Force Metadata Sync", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(AppTheme.dynamicAccent)
                    Spacer()
                    if library.isForcingMetadataSync {
                        ProgressView()
                            .tint(AppTheme.dynamicAccent)
                    }
                }
            }
            .disabled(library.isForcingMetadataSync)

        } header: {
            sectionHeader("Library")
        } footer: {
            Text("Re-scans your entire Documents folder — including \"Imported Music\" and any subfolders — plus any watched folders, then re-reads embedded tags and re-runs online metadata lookups for every imported track. Use this if tags look stale or after manually adding files outside the app.")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Car Mode Section

    private var carModeSection: some View {
        Section {
            // Car Mode toggle
            Toggle(isOn: $carModeEnabled) {
                Label("Car Mode", systemImage: "car.fill")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)

            if carModeEnabled {
                Text("Shows a large-button driving layout, accessible from the floating car icon or automatically when connected to a car stereo.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Hides the Car Mode button and disables automatic switching when connected to a car stereo.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            sectionHeader("Car Mode")
        }
        .listRowBackground(AppTheme.surface)
        .animation(.easeInOut(duration: 0.22), value: carModeEnabled)
    }

    // MARK: — Playback & Audio Section

    private var playbackAudioSection: some View {
        Section {
            // Crossfade (manual, fixed-duration). Mutually exclusive with Smart
            // Auto Crossfade — enabling one turns the other off; either one
            // drives an actual crossfade transition.
            Toggle(isOn: $player.audioSettings.crossfadeEnabled) {
                Label("Crossfade", systemImage: "waveform.path.ecg")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)
            .onChange(of: player.audioSettings.crossfadeEnabled) { on in
                if on { player.audioSettings.smartCrossfadeEnabled = false }
            }

            if player.audioSettings.crossfadeEnabled {
                Text("Songs will fade into each other over \(Int(player.audioSettings.crossfadeDuration))s. A smooth, uninterrupted listening experience.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Smart Auto Crossfade — independent top-level option (previously
            // nested under Crossfade, so it only worked when manual crossfade was
            // also on). Mutually exclusive with manual Crossfade.
            Toggle(isOn: $player.audioSettings.smartCrossfadeEnabled) {
                Label("Smart Auto Crossfade", systemImage: "metronome")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)
            .onChange(of: player.audioSettings.smartCrossfadeEnabled) { on in
                if on { player.audioSettings.crossfadeEnabled = false }
            }

            if player.audioSettings.smartCrossfadeEnabled {
                Text("Analyzes each track's BPM and beatmatches the outgoing and incoming songs, aligning the fade to the beat for a seamless DJ-style transition. Falls back to a normal crossfade when tempos are too far apart or unknown.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Crossfade duration — shown when EITHER mode is on (it's the base /
            // fallback duration that Smart Auto Crossfade adjusts around).
            if player.audioSettings.crossfadeActive {
                HStack {
                    Label("Duration", systemImage: "timer")
                        .foregroundStyle(AppTheme.textSecondary)
                        .font(AppTheme.bodyFont(size: 14))
                    Spacer()
                    Stepper(
                        value: $player.audioSettings.crossfadeDuration,
                        in: 1...10,
                        step: 1
                    ) {
                        Text("\(Int(player.audioSettings.crossfadeDuration))s")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                }
                .padding(.leading, 16)
            }

            // Gapless playback
            Toggle(isOn: $player.audioSettings.gaplessEnabled) {
                Label("Gapless Playback", systemImage: "infinity")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)

            if player.audioSettings.gaplessEnabled {
                Text("Tracks play back-to-back with no silence between them. Ideal for live albums and DJ mixes.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ReplayGain
            Toggle(isOn: $player.audioSettings.replayGainEnabled) {
                Label("ReplayGain", systemImage: "speaker.wave.3")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)

            if player.audioSettings.replayGainEnabled {
                Text("Normalises loudness across tracks so volume stays consistent. Reads REPLAYGAIN_TRACK_GAIN metadata when available.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Default speed
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Speed", systemImage: "hare")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(String(format: "%.2f×", player.audioSettings.speed))
                        .font(AppTheme.monoFont(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Slider(value: $player.audioSettings.speed, in: 0.5...2.0, step: 0.05)
                    .tint(AppTheme.dynamicAccent)
                HStack {
                    Text("0.5×").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text("2.0×").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                }
            }

            // Default pitch
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Pitch", systemImage: "music.quarternote.3")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(pitchLabel(player.audioSettings.pitchSemitones))
                        .font(AppTheme.monoFont(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Slider(value: $player.audioSettings.pitchSemitones, in: -12...12, step: 0.5)
                    .tint(AppTheme.dynamicAccent)
                HStack {
                    Text("−12 st").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text("+12 st").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                }
            }

            // Equalizer toggle
            Toggle(isOn: $player.audioSettings.equalizerEnabled) {
                Label("Equalizer", systemImage: "slider.vertical.3")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)

            // EQ Preset picker
            if player.audioSettings.equalizerEnabled {
                // Auto EQ toggle — when on, the preset switches automatically per-track
                // based on tempo (see EQPreset.auto(forBPM:)), so the manual picker
                // below is hidden to avoid implying a fixed preset is in effect.
                Toggle(isOn: $player.audioSettings.autoEQEnabled) {
                    Label("Auto EQ (by genre & tempo)", systemImage: "wand.and.stars")
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .tint(AppTheme.dynamicAccent)

                if player.audioSettings.autoEQEnabled {
                    Text("Automatically picks the best EQ preset for each track from its genre tag, falling back to its analyzed BPM when no genre is tagged.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.leading, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !player.audioSettings.autoEQEnabled {
                    HStack {
                        Label("EQ Preset", systemImage: "waveform")
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Picker("", selection: $player.audioSettings.eqPreset) {
                            ForEach(EQPreset.allCases) { preset in
                                Text(preset.displayName)
                                    .tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppTheme.dynamicAccent)
                        .onChange(of: player.audioSettings.eqPreset) { newPreset in
                            player.applyEQPreset(newPreset)
                        }
                    }
                }
            }

            // Bass Boost toggle
            Toggle(isOn: $player.audioSettings.bassBoostEnabled) {
                Label("Bass Boost", systemImage: "waveform.path")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)

            if player.audioSettings.bassBoostEnabled {
                Text("Boosts the 32 Hz and 64 Hz bands for deeper, punchier bass. Adjust the gain below to taste.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Bass Boost gain slider — only shown when enabled
            if player.audioSettings.bassBoostEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Boost Gain", systemImage: "speaker.plus")
                            .foregroundStyle(AppTheme.textSecondary)
                            .font(AppTheme.bodyFont(size: 14))
                        Spacer()
                        Text(String(format: "%.1f dB", player.audioSettings.bassBoostGain))
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Slider(value: $player.audioSettings.bassBoostGain, in: 0...15, step: 0.5)
                        .tint(AppTheme.dynamicAccent)
                    HStack {
                        Text("0 dB").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text("15 dB").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.leading, 16)
            }

            // Reverb toggle — on by default, applies live to whatever is playing.
            Toggle(isOn: $player.audioSettings.reverbEnabled) {
                Label("Reverb", systemImage: "circle.hexagonpath")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)

            if player.audioSettings.reverbEnabled {
                Text("Adds a real sense of space to playback. Changes apply instantly to the current track.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                HStack {
                    Label("Room", systemImage: "square.stack.3d.up")
                        .foregroundStyle(AppTheme.textSecondary)
                        .font(AppTheme.bodyFont(size: 14))
                    Spacer()
                    Picker("", selection: $player.audioSettings.reverbPreset) {
                        ForEach(ReverbRoomPreset.allCases) { preset in
                            Text(preset.displayName)
                                .tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.dynamicAccent)
                }
                .padding(.leading, 16)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Mix", systemImage: "dial.medium")
                            .foregroundStyle(AppTheme.textSecondary)
                            .font(AppTheme.bodyFont(size: 14))
                        Spacer()
                        Text("\(Int(player.audioSettings.reverbWetDryMix))%")
                            .font(AppTheme.monoFont(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Slider(value: $player.audioSettings.reverbWetDryMix, in: 0...100, step: 1)
                        .tint(AppTheme.dynamicAccent)
                    HStack {
                        Text("Dry").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text("Wet").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.leading, 16)
            }

            // Player error message (if any)
            if let error = player.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

        } header: {
            sectionHeader("Playback & Audio")
        }
        .listRowBackground(AppTheme.surface)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.crossfadeEnabled)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.gaplessEnabled)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.replayGainEnabled)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.bassBoostEnabled)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.reverbEnabled)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.smartCrossfadeEnabled)
    }

    // MARK: — Streaming & Downloads Section

    @State private var showHealthResult = false
    @State private var healthOK = false

    private var streamingDownloadsSection: some View {
        Section {
            #if DEBUG
            // Status row — only meaningful in DEBUG since `isConfigured` is
            // hardcoded `true` for release builds (a default bridge URL is
            // always baked in), so it'd always read "Configured" otherwise.
            HStack {
                Label("Bridge Server", systemImage: "server.rack")
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(streaming.isConfigured ? "Configured" : "Not configured")
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(streaming.isConfigured ? AppTheme.success : AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (streaming.isConfigured ? AppTheme.success : AppTheme.textSecondary).opacity(0.15),
                        in: Capsule()
                    )
            }

            // Server URL and API key point at the developer's personal backend
            // (a default URL is baked in via `StreamingService.defaultBridgeURL`,
            // so the app works without any user input). These overrides are only
            // useful for local development/testing against a different bridge,
            // so they're hidden from end users entirely.
            // Server URL field
            HStack {
                Label("Server URL", systemImage: "link")
                    .foregroundStyle(AppTheme.textPrimary)
                TextField("http://192.168.1.x:7333", text: Binding(
                    get: { streaming.bridgeURL },
                    set: { streaming.bridgeURL = $0 }
                ))
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppTheme.textSecondary)
            }

            // API Key (optional)
            HStack {
                Label("API Key (optional)", systemImage: "key")
                    .foregroundStyle(AppTheme.textPrimary)
                SecureField("Leave blank if not set", text: Binding(
                    get: { streaming.apiKey },
                    set: { streaming.apiKey = $0 }
                ))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppTheme.textSecondary)
            }
            #endif

            // Audio Format picker
            HStack {
                Label("Audio Format", systemImage: "waveform")
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Picker("Audio Format", selection: Binding(
                    get: { streaming.preferredFormat },
                    set: { streaming.preferredFormat = $0 }
                )) {
                    ForEach(StreamingService.availableFormats, id: \.value) { fmt in
                        Text(fmt.label).tag(fmt.value)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.dynamicAccent)
            }

            // Test connection
            Button {
                Task {
                    let ok = await streaming.checkHealth()
                    healthOK = ok
                    showHealthResult = true
                }
            } label: {
                HStack {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(AppTheme.dynamicAccent)
                    Spacer()
                    if showHealthResult {
                        Image(systemName: healthOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(healthOK ? AppTheme.success : AppTheme.error)
                    }
                }
            }

            // YouTube Data API key — only relevant when signed in, since the
            // key is stored server-side on the user's account.
            if account.isLoggedIn {
                youtubeAPIKeySection
            }

        } header: {
            sectionHeader("Streaming & Downloads")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — yt-dlp Section

    private var ytdlpSection: some View {
        Group {
            Section {
                Toggle(isOn: $ytdlpUseAria2) {
                    Label("Use aria2 downloader", systemImage: "bolt.horizontal.circle")
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .tint(AppTheme.dynamicAccent)

                Text(ytdlpUseAria2
                     ? "Downloads use aria2 with multiple parallel connections. This can help on networks where YouTube throttles single connections — but on a fast, un-throttled connection the built-in downloader is usually faster."
                     : "Downloads use yt-dlp's built-in downloader (recommended — benchmarked faster on most connections). Turn this on only if your network throttles single downloads.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } header: {
                sectionHeader("Download Engine")
            } footer: {
                Text("aria2 opens many connections per download. It bypasses per-connection throttling on some networks, but adds overhead that makes it slower when a single connection is already fast.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            // Audio format also governs yt-dlp's output, so surface it here too.
            Section {
                HStack {
                    Label("Audio Format", systemImage: "waveform")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Picker("Audio Format", selection: Binding(
                        get: { streaming.preferredFormat },
                        set: { streaming.preferredFormat = $0 }
                    )) {
                        ForEach(StreamingService.availableFormats, id: \.value) { fmt in
                            Text(fmt.label).tag(fmt.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.dynamicAccent)
                }
            } header: {
                sectionHeader("Format")
            } footer: {
                Text("Preferred audio format for downloads (yt-dlp -x --audio-format). Highest quality is used for every download.")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            // YouTube auth — cookies + Data API key — both feed yt-dlp lookups.
            if account.isLoggedIn {
                Section {
                    NavigationLink(destination: CookiesFileView()) {
                        Label("YouTube Cookies", systemImage: "doc.text")
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    NavigationLink(destination: YoutubeApiKeyView()) {
                        Label("YouTube API Key", systemImage: "key")
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                } header: {
                    sectionHeader("YouTube Authentication")
                } footer: {
                    Text("Upload a cookies.txt to download age-restricted content and avoid bot checks. Add a YouTube Data API key for full playlist resolution.")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: ytdlpUseAria2)
    }

    // MARK: — YouTube API Key Rows

    /// Masked display of the configured key (or a placeholder if none set).
    private var youtubeKeyDisplay: String {
        guard let config = youtubeKeyConfig, config.configured, let masked = config.apiKey else {
            return "Not set"
        }
        return masked
    }

    @ViewBuilder
    private var youtubeAPIKeySection: some View {
        // Status / masked key row
        HStack {
            Label("YouTube API Key", systemImage: "key.horizontal")
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            Text(youtubeKeyDisplay)
                .font(AppTheme.monoFont(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
        }

        // Entry field for setting/replacing the key — hidden once a key is
        // configured, unless that key's quota has been exhausted (so the
        // user can drop in a replacement).
        if youtubeKeyConfig?.configured != true || youtubeKeyQuotaExceeded {
            HStack {
                Label("Set Key", systemImage: "pencil")
                    .foregroundStyle(AppTheme.textPrimary)
                SecureField("Paste YouTube Data API v3 key", text: $youtubeKeyInput)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if !youtubeKeyInput.isEmpty {
                Button {
                    Task {
                        isSavingYouTubeKey = true
                        let ok = await account.setYoutubeApiKey(youtubeKeyInput)
                        isSavingYouTubeKey = false
                        if ok {
                            youtubeKeyInput = ""
                            youtubeKeyQuotaExceeded = false
                            ToastCenter.shared.show("YouTube API key saved", category: .success, icon: "key.horizontal")
                            await refreshYouTubeKeyStatus()
                        } else {
                            ToastCenter.shared.show("Couldn't save key — check connection", category: .error, icon: "exclamationmark.triangle")
                        }
                    }
                } label: {
                    HStack {
                        Label("Save Key", systemImage: "checkmark.circle")
                            .foregroundStyle(AppTheme.dynamicAccent)
                        Spacer()
                        if isSavingYouTubeKey {
                            ProgressView().tint(AppTheme.dynamicAccent)
                        }
                    }
                }
                .disabled(isSavingYouTubeKey)
            }
        }

        // Validate API Key button — always visible once a key is configured.
        Button {
            Task {
                isValidatingYouTubeKey = true
                let status = await account.validateYouTubeAPIKey()
                isValidatingYouTubeKey = false
                switch status {
                case "valid":
                    youtubeKeyQuotaExceeded = false
                    ToastCenter.shared.show("YouTube API key is valid", category: .success, icon: "checkmark.seal")
                case "invalid":
                    ToastCenter.shared.show("YouTube API key is invalid", category: .error, icon: "xmark.seal")
                case "quota_exceeded":
                    youtubeKeyQuotaExceeded = true
                    ToastCenter.shared.show("YouTube API quota exceeded for today", category: .warning, icon: "exclamationmark.triangle")
                default:
                    ToastCenter.shared.show("Couldn't validate key — check connection", category: .error, icon: "wifi.exclamationmark")
                }
            }
        } label: {
            HStack {
                Label("Validate API Key", systemImage: "checkmark.shield")
                    .foregroundStyle(AppTheme.dynamicAccent)
                Spacer()
                if isValidatingYouTubeKey {
                    ProgressView().tint(AppTheme.dynamicAccent)
                }
            }
        }
        .disabled(isValidatingYouTubeKey || youtubeKeyConfig?.configured != true)

        // Remove key
        if youtubeKeyConfig?.configured == true {
            Button(role: .destructive) {
                Task {
                    let ok = await account.deleteYoutubeApiKey()
                    if ok {
                        youtubeKeyQuotaExceeded = false
                        ToastCenter.shared.show("YouTube API key removed", category: .info, icon: "key.horizontal")
                        await refreshYouTubeKeyStatus()
                    } else {
                        ToastCenter.shared.show("Couldn't remove key — check connection", category: .error, icon: "exclamationmark.triangle")
                    }
                }
            } label: {
                Label("Remove Key", systemImage: "trash")
                    .foregroundStyle(AppTheme.error)
            }
        }

        Text("Used by Lumisound's bridge to enumerate full YouTube playlists. Falls back to a shared server key if unset. Never displayed in full once saved.")
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.leading, 16)
    }

    // MARK: — Sleep Timer Section

    private var sleepTimerSection: some View {
        Section {
            if sleepTimer.isActive {
                HStack {
                    Label("Active — \(sleepTimer.formattedRemaining)", systemImage: "moon.zzz")
                        .foregroundStyle(AppTheme.textPrimary)
                        .font(.system(.subheadline).monospacedDigit())
                    Spacer()
                    Button("Cancel") {
                        sleepTimer.cancel()
                        ToastCenter.shared.show("Sleep timer cancelled", category: .info, icon: "moon.zzz")
                    }
                    .foregroundStyle(AppTheme.warning)
                }
            } else {
                Picker("Duration", selection: $sleepTimer.selectedDuration) {
                    ForEach(SleepTimerService.presets, id: \.seconds) { preset in
                        Text(preset.label).tag(preset.seconds)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppTheme.dynamicAccent)
                .foregroundStyle(AppTheme.textPrimary)

                Button {
                    sleepTimer.start()
                    ToastCenter.shared.show("Sleep timer started", category: .success, icon: "moon.zzz.fill")
                } label: {
                    Label("Start Sleep Timer", systemImage: "moon.zzz")
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
            }
        } header: {
            sectionHeader("Sleep Timer")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Appearance Section

    private var appearanceSection: some View {
        Section {
            NavigationLink(destination: AppearanceView()) {
                HStack {
                    Label("Appearance", systemImage: "paintbrush")
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    // Current accent preview swatch
                    Circle()
                        .fill(AppTheme.dynamicAccent)
                        .frame(width: 22, height: 22)
                        .shadow(color: AppTheme.dynamicAccent.opacity(0.4), radius: 4, x: 0, y: 2)
                }
            }
            NavigationLink(destination: BackgroundSettingsView()) {
                Label("Gallery Background", systemImage: "photo.on.rectangle")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            NavigationLink(destination: GlassSettingsView()) {
                Label("Liquid Glass", systemImage: "circle.hexagongrid.fill")
                    .foregroundStyle(AppTheme.textPrimary)
            }
        } header: {
            sectionHeader("Appearance")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — App Updates Section

    private var updatesSection: some View {
        Section {
            // Version info row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Version")
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(updater.currentVersion)
                        .font(AppTheme.monoFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                if updater.updateAvailable, let latest = updater.latestVersion {
                    Text("→ \(latest)")
                        .font(AppTheme.monoFont(size: 13))
                        .foregroundStyle(AppTheme.success)
                }
            }

            // Download update button — only when available
            if updater.updateAvailable {
                Button {
                    updater.openReleasePage()
                } label: {
                    Label(
                        updater.directDownloadURL != nil
                            ? "Download v\(updater.latestVersion ?? "") IPA"
                            : "Download Update",
                        systemImage: "arrow.down.circle"
                    )
                    .foregroundStyle(AppTheme.dynamicAccent)
                }
            }

            // Check for updates button
            Button {
                Task { await updater.checkForUpdates() }
            } label: {
                HStack {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                        .foregroundStyle(AppTheme.dynamicAccent)
                    Spacer()
                    if updater.isChecking {
                        ProgressView()
                            .tint(AppTheme.dynamicAccent)
                    }
                }
            }
            .disabled(updater.isChecking)

        } header: {
            sectionHeader("App Updates")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Help Section

    private var helpSection: some View {
        Section {
            NavigationLink(destination: SettingsHelpView()) {
                Label("Help & Feature Guide", systemImage: "questionmark.circle")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            NavigationLink(destination: BugReportView()) {
                Label("Report a Bug", systemImage: "ladybug")
                    .foregroundStyle(AppTheme.textPrimary)
            }
        } header: {
            sectionHeader("Help")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — About Section

    private var aboutSection: some View {
        Section {
            LabeledContent("App") {
                Text("Lumisound")
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

            HStack {
                Label("Version", systemImage: updater.updateStatusIcon)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(updater.currentVersion)
                        .font(AppTheme.monoFont(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(updater.updateStatusText)
                        .font(.caption)
                        .foregroundStyle(updater.updateStatusColor)
                }
            }

            Button {
                Task { await updater.checkForUpdates() }
            } label: {
                HStack {
                    Label("Check Now", systemImage: "arrow.clockwise")
                        .foregroundStyle(AppTheme.dynamicAccent)
                    Spacer()
                    if updater.isChecking {
                        ProgressView()
                            .tint(AppTheme.dynamicAccent)
                    }
                }
            }
            .disabled(updater.isChecking)

            if !WidgetDataService.shared.isAppGroupAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Widgets Unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("This build can't share data with its Lock Screen and Home Screen widgets, so they'll stay on their placeholder. This usually means the App Group entitlement (group.com.lumisound.ios) wasn't preserved when this app was signed — re-signing tools need to include that App Group in the provisioning profile for widgets to work.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 2)
            }

            // Open Source Libraries
            VStack(alignment: .leading, spacing: 6) {
                Text("Open Source Libraries")
                    .font(AppTheme.bodyFont())
                    .foregroundStyle(AppTheme.textPrimary)
                ForEach(["AVFoundation", "SwiftUI", "MediaPlayer"], id: \.self) { lib in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.success)
                        Text(lib)
                            .font(AppTheme.bodyFont(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .padding(.vertical, 4)

            // Credit line
            HStack {
                Spacer()
                Text("Built with AVFoundation & SwiftUI")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .italic()
                Spacer()
            }

        } header: {
            sectionHeader("About")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.bodyFont(size: 11))
            .foregroundStyle(AppTheme.textSecondary)
            .kerning(0.8)
    }

    private var mediaAccessStatusText: String {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:    return "Allowed"
        case .denied:        return "Denied"
        case .restricted:    return "Restricted"
        case .notDetermined: return "Not Asked"
        @unknown default:    return "Unknown"
        }
    }

    private var mediaAccessStatusColor: Color {
        MPMediaLibrary.authorizationStatus() == .authorized
            ? AppTheme.success
            : AppTheme.warning
    }

    private func pitchLabel(_ semitones: Float) -> String {
        if semitones == 0 { return "0 st" }
        let sign = semitones > 0 ? "+" : ""
        return String(format: "%@%.1f st", sign, semitones)
    }

    // MARK: — YouTube API Key Helpers

    /// Refreshes the masked YouTube API key status from the bridge.
    private func refreshYouTubeKeyStatus() async {
        guard account.isLoggedIn else { return }
        youtubeKeyConfig = await account.fetchYoutubeApiKey()
    }

    /// Starts a 5-minute repeating timer that checks whether the user's
    /// YouTube API key has been exposed (e.g. leaked in a public commit/log),
    /// surfacing a warning toast if so. Runs only while Settings is visible.
    private func startYouTubeExposureMonitor() {
        guard youtubeExposureTimer == nil else { return }

        // Immediate first check, then repeat every 5 minutes.
        Task { await checkYouTubeKeyExposureAndNotify() }

        let accountService = account
        let timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak accountService] _ in
            guard let accountService else { return }
            Task { @MainActor in
                await SettingsView.checkExposureAndNotify(account: accountService)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        youtubeExposureTimer = timer
    }

    private func checkYouTubeKeyExposureAndNotify() async {
        await Self.checkExposureAndNotify(account: account)
    }

    /// Checks for a leaked YouTube API key and shows a warning toast if found.
    /// Takes `account` explicitly so the recurring `Timer` closure can capture
    /// it weakly instead of capturing the whole view.
    @MainActor
    private static func checkExposureAndNotify(account: AccountService) async {
        guard account.isLoggedIn else { return }
        let result = await account.checkYouTubeKeyExposure()
        if result.exposed {
            let detail = result.detail.isEmpty
                ? "Your YouTube API key may be publicly exposed."
                : result.detail
            ToastCenter.shared.show(
                "\(detail) Consider regenerating your key in Google Cloud Console.",
                category: .warning,
                icon: "exclamationmark.shield"
            )
        }
    }
}
