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

    @State private var showLogin = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                // Update banner — only visible when an update is available
                if updater.updateAvailable {
                    Section {
                        UpdateBannerView()
                            .environmentObject(updater)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                accountSection
                librarySection
                playbackSection
                streamingSection
                sleepTimerSection
                audioSection
                appearanceSection
                updatesSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showLogin) {
                LoginView()
                    .environmentObject(account)
            }
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
                                            colors: [AppTheme.accent, AppTheme.accentSoft],
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
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 4, x: 0, y: 2)
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
                        .foregroundStyle(AppTheme.accent)
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
            .tint(AppTheme.accent)

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
                        .foregroundStyle(AppTheme.accent)
                }
            } else {
                Button {
                    library.scanMediaLibrary()
                } label: {
                    HStack {
                        Label("Scan Library", systemImage: "arrow.clockwise")
                            .foregroundStyle(AppTheme.accent)
                        Spacer()
                        if library.isScanning {
                            ProgressView()
                                .tint(AppTheme.accent)
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

        } header: {
            sectionHeader("Library")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Playback Section

    private var playbackSection: some View {
        Section {
            // Crossfade toggle
            Toggle(isOn: $player.audioSettings.crossfadeEnabled) {
                Label("Crossfade", systemImage: "waveform.path.ecg")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.accent)

            if player.audioSettings.crossfadeEnabled {
                Text("Songs will fade into each other over \(Int(player.audioSettings.crossfadeDuration))s. A smooth, uninterrupted listening experience.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Crossfade duration — only shown when crossfade is on
            if player.audioSettings.crossfadeEnabled {
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
            .tint(AppTheme.accent)

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
            .tint(AppTheme.accent)

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
                    .tint(AppTheme.accent)
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
                    .tint(AppTheme.accent)
                HStack {
                    Text("−12 st").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Text("+12 st").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                }
            }

        } header: {
            sectionHeader("Playback")
        }
        .listRowBackground(AppTheme.surface)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.crossfadeEnabled)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.gaplessEnabled)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.replayGainEnabled)
    }

    // MARK: — Streaming Section

    @State private var showHealthResult = false
    @State private var healthOK = false

    private var streamingSection: some View {
        Section {
            // Status row
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
                .tint(AppTheme.accent)
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
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    if showHealthResult {
                        Image(systemName: healthOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(healthOK ? AppTheme.success : AppTheme.error)
                    }
                }
            }

        } header: {
            sectionHeader("Streaming")
        }
        .listRowBackground(AppTheme.surface)
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
                .tint(AppTheme.accent)
                .foregroundStyle(AppTheme.textPrimary)

                Button {
                    sleepTimer.start()
                } label: {
                    Label("Start Sleep Timer", systemImage: "moon.zzz")
                        .foregroundStyle(AppTheme.accent)
                }
            }
        } header: {
            sectionHeader("Sleep Timer")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — Audio Section

    private var audioSection: some View {
        Section {
            // Equalizer toggle
            Toggle(isOn: $player.audioSettings.equalizerEnabled) {
                Label("Equalizer", systemImage: "slider.vertical.3")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.accent)

            // EQ Preset picker
            if player.audioSettings.equalizerEnabled {
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
                    .tint(AppTheme.accent)
                    .onChange(of: player.audioSettings.eqPreset) { newPreset in
                        player.applyEQPreset(newPreset)
                    }
                }
            }

            // Bass Boost toggle
            Toggle(isOn: $player.audioSettings.bassBoostEnabled) {
                Label("Bass Boost", systemImage: "waveform.path")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.accent)

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
                        .tint(AppTheme.accent)
                    HStack {
                        Text("0 dB").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text("15 dB").font(AppTheme.monoFont(size: 11)).foregroundStyle(AppTheme.textSecondary)
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
            sectionHeader("Audio")
        }
        .listRowBackground(AppTheme.surface)
        .animation(.easeInOut(duration: 0.22), value: player.audioSettings.bassBoostEnabled)
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
                            ? "Download v\(updater.latestVersion!) IPA"
                            : "Download Update",
                        systemImage: "arrow.down.circle"
                    )
                    .foregroundStyle(AppTheme.accent)
                }
            }

            // Check for updates button
            Button {
                Task { await updater.checkForUpdates() }
            } label: {
                HStack {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    if updater.isChecking {
                        ProgressView()
                            .tint(AppTheme.accent)
                    }
                }
            }
            .disabled(updater.isChecking)

        } header: {
            sectionHeader("App Updates")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: — About Section

    private var aboutSection: some View {
        Section {
            LabeledContent("App") {
                Text("Stash Opus Player")
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
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    if updater.isChecking {
                        ProgressView()
                            .tint(AppTheme.accent)
                    }
                }
            }
            .disabled(updater.isChecking)

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
}
