import SwiftUI

/// Technical audio format details for the currently playing track — codec/
/// container, sample rate, bit depth, bitrate, channels, file size — plus a
/// note when playback is running through the AVPlayer compatibility
/// fallback (opus/webm/ogg), where EQ/pitch/crossfade/effects don't apply.
struct FormatInfoSheet: View {
    let song: Song?
    let isUsingFallback: Bool
    @EnvironmentObject private var library: LibraryManager
    @Environment(\.dismiss) private var dismiss
    @State private var details: AudioFormatDetails?
    @State private var isConverting = false

    var body: some View {
        NavigationStack {
            List {
                if let details {
                    Section {
                        badgeRow(details)
                    }
                    .listRowBackground(Color.clear)

                    Section("Format") {
                        row("Container", details.container)
                        if let sampleRateText = details.sampleRateText {
                            row("Sample Rate", sampleRateText)
                        }
                        if let bitDepth = details.bitDepth {
                            row("Bit Depth", "\(bitDepth)-bit")
                        }
                        if let bitrateKbps = details.bitrateKbps {
                            row("Bitrate", "\(bitrateKbps) kbps")
                        }
                        if let channelCount = details.channelCount {
                            row("Channels", channelCount == 1 ? "Mono" : channelCount == 2 ? "Stereo" : "\(channelCount)")
                        }
                        if let fileSizeText = details.fileSizeText {
                            row("File Size", fileSizeText)
                        }
                    }

                    if details.isPlayingViaCompatibilityFallback {
                        Section {
                            Label(
                                "This format plays through a compatibility mode. Equalizer, pitch, crossfade, gapless, ReplayGain, and special effects don't apply while it's active.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(AppTheme.warning)

                            if let song, song.url?.isFileURL == true {
                                Button {
                                    isConverting = true
                                    Task {
                                        await library.convertImportedSongFormat(songID: song.id)
                                        isConverting = false
                                    }
                                } label: {
                                    if isConverting {
                                        HStack {
                                            ProgressView().controlSize(.small)
                                            Text("Converting…")
                                        }
                                    } else {
                                        Label("Convert Now", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                }
                                .disabled(isConverting)
                            }
                        }
                        .listRowBackground(AppTheme.warning.opacity(0.1))
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Format Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: song?.id) {
                details = AudioFormatDetails.inspect(song: song, isUsingFallback: isUsingFallback)
            }
        }
    }

    @ViewBuilder
    private func badgeRow(_ details: AudioFormatDetails) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: details.isLossless ? "checkmark.seal.fill" : "waveform")
                    .font(.system(size: 32))
                    .foregroundStyle(details.isLossless ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                Text(details.qualityLabel)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
        }
    }
}
