import MediaPlayer
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    // MARK: Dependencies

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                librarySection
                playbackSection
                audioSection
                appearanceSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: — Library Section

    private var librarySection: some View {
        Section {
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

            // ReplayGain
            Toggle(isOn: $player.audioSettings.replayGainEnabled) {
                Label("ReplayGain", systemImage: "speaker.wave.3")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.accent)

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
        } header: {
            sectionHeader("Appearance")
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

            LabeledContent("Version") {
                Text("1.0.0")
                    .font(AppTheme.monoFont(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .foregroundStyle(AppTheme.textPrimary)

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
