import SwiftUI

// MARK: - TransferPlaybackSheet
//
// Device picker for cross-device playback handoff (see
// AccountService+PlaybackTransfer.swift / main.py's /user/devices and
// /user/playback/transfer). Lists every device this account has registered
// for push (GET /user/devices) other than this one (matched by the locally-
// cached APNs token, same UserDefaults key registerPushToken already
// writes), and sends the currently-playing track/position to whichever one
// is tapped.
struct TransferPlaybackSheet: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [RegisteredDevice] = []
    @State private var isLoading = true
    @State private var transferringDeviceID: String?
    @State private var errorText: String?

    private static let deviceTokenKey = "apns_device_token_hex"

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if otherDevices.isEmpty {
                    emptyState
                } else {
                    List(otherDevices) { device in
                        Button {
                            transfer(to: device)
                        } label: {
                            HStack {
                                Image(systemName: iconName(for: device.platform))
                                    .foregroundStyle(AppTheme.dynamicAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.displayName)
                                        .foregroundStyle(AppTheme.textPrimary)
                                    if let lastSeen = device.lastSeenAt {
                                        Text("Last seen \(lastSeen)")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                                Spacer()
                                if transferringDeviceID == device.id {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(transferringDeviceID != nil)
                    }
                    .listStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(AppTheme.surface)
                }
            }
            .navigationTitle("Transfer Playback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var otherDevices: [RegisteredDevice] {
        let thisDeviceToken = UserDefaults.standard.string(forKey: Self.deviceTokenKey)
        return devices.filter { $0.deviceToken != thisDeviceToken }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.textSecondary)
            Text("No Other Devices")
                .font(.headline)
            Text("Log in on another device with notifications enabled to transfer playback to it.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func iconName(for platform: String) -> String {
        platform == "android" ? "candybarphone" : "iphone"
    }

    private func load() async {
        isLoading = true
        devices = await account.fetchDevices()
        isLoading = false
    }

    private func transfer(to device: RegisteredDevice) {
        guard let song = player.currentSong else { return }
        transferringDeviceID = device.id
        errorText = nil
        Task {
            let success = await account.transferPlayback(
                song: song,
                position: player.progress.position,
                duration: player.progress.duration,
                isPlaying: player.isPlaying,
                to: device,
                bpm: song.bpm
            )
            transferringDeviceID = nil
            if success {
                dismiss()
            } else {
                errorText = account.errorMessage ?? "Couldn't transfer playback."
            }
        }
    }
}
