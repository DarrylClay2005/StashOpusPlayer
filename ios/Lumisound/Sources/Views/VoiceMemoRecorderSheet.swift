import AVFoundation
import SwiftUI

/// Record, play back, or delete a `VoiceMemoStore` voice note for one
/// `TrackBookmark`. Same `AVAudioRecorder`/mic-permission pattern as
/// `HumToSearchView`/`NameThatTuneView`, just recording to keep rather
/// than to analyze.
struct VoiceMemoRecorderSheet: View {
    let bookmark: TrackBookmark
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case idle
        case recording
        case permissionDenied
        case error(String)
    }

    @State private var stage: Stage = .idle
    @State private var recorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var elapsed: TimeInterval = 0
    @State private var recordTimer: Timer?
    @State private var hasMemo = false
    @State private var player: AVAudioPlayer?
    @State private var isPlayingBack = false

    private static let maxRecordSeconds: TimeInterval = 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(bookmark.label)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                switch stage {
                case .idle: idleState
                case .recording: recordingState
                case .permissionDenied: permissionDeniedState
                case .error(let message): errorState(message)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GalleryBackgroundView().ignoresSafeArea())
            .navigationTitle("Voice Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { hasMemo = VoiceMemoStore.shared.hasMemo(for: bookmark.id) }
            .onDisappear { cancelRecordingIfNeeded(); player?.stop() }
        }
    }

    private var idleState: some View {
        VStack(spacing: 20) {
            Image(systemName: hasMemo ? "waveform.circle.fill" : "mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.dynamicAccent)

            if hasMemo {
                HStack(spacing: 16) {
                    Button {
                        togglePlayback()
                    } label: {
                        Label(isPlayingBack ? "Stop" : "Play", systemImage: isPlayingBack ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.dynamicAccent)

                    Button(role: .destructive) {
                        VoiceMemoStore.shared.deleteMemo(for: bookmark.id)
                        hasMemo = false
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button {
                startRecording()
            } label: {
                Label(hasMemo ? "Re-record" : "Record", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.dynamicAccent)
            .padding(.horizontal, 24)
        }
    }

    private var recordingState: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.dynamicAccent)
            Text(formattedTime(elapsed))
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)

            Button {
                finishRecording()
            } label: {
                Label("Stop & Save", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.dynamicAccent)
            .padding(.horizontal, 24)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.warning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { stage = .idle }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.dynamicAccent)
        }
    }

    private var permissionDeniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Microphone Access Needed")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    stage = .permissionDenied
                    return
                }
                beginRecordingSession()
            }
        }
    }

    private func beginRecordingSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            stage = .error("Couldn't access the microphone: \(error.localizedDescription)")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_memo_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.record(forDuration: Self.maxRecordSeconds)
            recorder = newRecorder
            recordingURL = url
        } catch {
            stage = .error("Couldn't start recording: \(error.localizedDescription)")
            return
        }

        elapsed = 0
        stage = .recording
        recordTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsed += 0.1
            if elapsed >= Self.maxRecordSeconds {
                finishRecording()
            }
        }
    }

    private func finishRecording() {
        recordTimer?.invalidate()
        recordTimer = nil
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = recordingURL else {
            stage = .idle
            return
        }
        do {
            try VoiceMemoStore.shared.saveMemo(from: url, for: bookmark.id)
            hasMemo = true
        } catch {
            stage = .error("Couldn't save the recording: \(error.localizedDescription)")
            return
        }
        stage = .idle
    }

    private func cancelRecordingIfNeeded() {
        recordTimer?.invalidate()
        recordTimer = nil
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlayingBack {
            player?.stop()
            isPlayingBack = false
            return
        }
        guard let url = VoiceMemoStore.shared.memoURL(for: bookmark.id) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.play()
            player = newPlayer
            isPlayingBack = true
        } catch {
            stage = .error("Couldn't play the recording: \(error.localizedDescription)")
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
