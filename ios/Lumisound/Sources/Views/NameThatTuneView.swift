import AVFoundation
import SwiftUI

/// "Name That Tune" — identifies whatever's playing near the device using
/// the microphone, reusing the exact same fingerprint-identification
/// pipeline `AcoustIDService` already exercises for fixing a local file's
/// wrong tags (POST /api/fingerprint/identify — Chromaprint + the
/// AcoustID/MusicBrainz database). The only new piece here is capturing a
/// short AAC clip from the mic instead of trimming an existing file; the
/// upload/parse/error handling is shared via
/// `AcoustIDService.identify(recordingURL:)`. Distinct from
/// `HumToSearchView`/`PitchContourService`: that's a best-effort melodic
/// match against the user's OWN library from a hummed approximation; this
/// is precise fingerprint recognition of a real recording, same as Shazam,
/// against the same AcoustID/MusicBrainz database used elsewhere in the
/// app — same "requires a personal AcoustID key" constraint, since
/// `AcoustIDService` has no server-wide fallback key.
struct NameThatTuneView: View {
    @EnvironmentObject private var streaming: StreamingService

    private enum Stage {
        case idle
        case recording
        case identifying
        case result(AcoustIDService.Match)
        case noMatch
        case permissionDenied
        case error(String)
    }

    @State private var stage: Stage = .idle
    @State private var recorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var elapsed: TimeInterval = 0
    @State private var recordTimer: Timer?
    @State private var showSearch = false
    @State private var searchQuery = ""

    private static let recordSeconds: TimeInterval = 12

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch stage {
                case .idle: idleState
                case .recording: recordingState
                case .identifying: identifyingState
                case .result(let match): resultState(match)
                case .noMatch: noMatchState
                case .permissionDenied: permissionDeniedState
                case .error(let message): errorState(message)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GalleryBackgroundView().ignoresSafeArea())
            .navigationTitle("Name That Tune")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { cancelRecordingIfNeeded() }
        }
        .sheet(isPresented: $showSearch) {
            StreamSearchView(initialSearchText: searchQuery)
                .environmentObject(streaming)
        }
    }

    // MARK: - States

    private var idleState: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.dynamicAccent)
            Text("Name That Tune")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text("Hold the phone near the music for a few seconds — this identifies the actual recording, not a hum or whistle.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button {
                startRecording()
            } label: {
                Label("Listen", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.dynamicAccent)
            .padding(.horizontal, 24)
        }
    }

    private var recordingState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(AppTheme.elevatedSurface, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: elapsed / Self.recordSeconds)
                    .stroke(AppTheme.dynamicAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: elapsed)
                Image(systemName: "waveform")
                    .font(.system(size: 32))
                    .foregroundStyle(AppTheme.dynamicAccent)
            }
            .frame(width: 100, height: 100)

            Text("Listening…")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Button("Cancel") {
                cancelRecordingIfNeeded()
                stage = .idle
            }
            .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var identifyingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Identifying…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func resultState(_ match: AcoustIDService.Match) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            VStack(spacing: 4) {
                Text(match.title)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if let artist = match.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if let album = match.album {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Button {
                searchQuery = [match.title, match.artist].compactMap { $0 }.joined(separator: " ")
                showSearch = true
            } label: {
                Label("Find & Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.dynamicAccent)
            .padding(.horizontal, 24)

            Button("Listen Again") { stage = .idle }
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var noMatchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Couldn't identify that one")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text("Try getting closer to the source, or wait for a clearer, less noisy section.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { stage = .idle }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.dynamicAccent)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
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
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.textSecondary)
            Text("Microphone Access Needed")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            Text("Grant microphone access in Settings to identify what's playing.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
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

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("name_that_tune_\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.record(forDuration: Self.recordSeconds)
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
            if elapsed >= Self.recordSeconds {
                finishRecordingAndIdentify()
            }
        }
    }

    private func finishRecordingAndIdentify() {
        recordTimer?.invalidate()
        recordTimer = nil
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url = recordingURL else {
            stage = .idle
            return
        }
        stage = .identifying
        Task {
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let match = try await AcoustIDService.shared.identify(recordingURL: url)
                stage = .result(match)
            } catch let error as AcoustIDService.IdentifyError {
                if case .notMatched = error {
                    stage = .noMatch
                } else {
                    stage = .error(error.localizedDescription)
                }
            } catch {
                stage = .error(error.localizedDescription)
            }
        }
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
}
