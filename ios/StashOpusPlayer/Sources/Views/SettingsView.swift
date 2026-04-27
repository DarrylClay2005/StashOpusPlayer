import MediaPlayer
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: MusicLibraryStore
    @EnvironmentObject private var player: AudioPlayerManager

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    HStack {
                        Text("Media Access")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }

                    Button("Request Access and Scan") {
                        library.requestAccessAndScan()
                    }

                    LabeledContent("Songs", value: "\(library.allSongs.count)")
                    LabeledContent("Artists", value: "\(library.artists.count)")
                    LabeledContent("Albums", value: "\(library.albums.count)")
                }

                Section("Playback") {
                    Toggle("Shuffle", isOn: Binding(
                        get: { player.shuffleEnabled },
                        set: { value in
                            if value != player.shuffleEnabled {
                                player.toggleShuffle()
                            }
                        }
                    ))
                    .tint(AppTheme.accent)

                    Button("Repeat: \(player.repeatMode.title)") {
                        player.cycleRepeatMode()
                    }
                }

                if let error = player.errorMessage {
                    Section("Player") {
                        Text(error)
                            .foregroundStyle(AppTheme.warning)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Settings")
        }
    }

    private var statusText: String {
        switch library.authorizationStatus {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Asked"
        @unknown default: return "Unknown"
        }
    }

    private var statusColor: Color {
        library.authorizationStatus == .authorized ? AppTheme.success : AppTheme.warning
    }
}
