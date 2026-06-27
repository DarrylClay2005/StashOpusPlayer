import SwiftUI
import AVFoundation

// MARK: - TVPlayContext (queue + where to start)

struct TVPlayContext: Hashable {
    let queue: [TVPlayable]
    let startID: String
}

// MARK: - TVPlayerModel

@MainActor
final class TVPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var currentIndex = 0
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published private(set) var queue: [TVPlayable] = []

    let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?

    var current: TVPlayable? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }

    func start(context: TVPlayContext) {
        guard queue.isEmpty else { return }  // start once
        queue = context.queue
        currentIndex = queue.firstIndex(where: { $0.id == context.startID }) ?? 0
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        setupObservers()
        loadCurrent()
    }

    private func setupObservers() {
        if endObserver == nil {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.next() }
            }
        }
        // Drives the scrubber + elapsed/remaining time.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.duration = d
                }
            }
        }
        // Keeps play/pause + the loading spinner in sync with real playback.
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = player.timeControlStatus == .playing
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    private func loadCurrent() {
        guard let item = current else { return }
        position = 0
        duration = 0
        isBuffering = true
        let asset: AVURLAsset
        if let token = item.authToken {
            asset = AVURLAsset(url: item.streamURL, options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]
            ])
        } else {
            asset = AVURLAsset(url: item.streamURL)
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        player.play()
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    func next() {
        guard currentIndex + 1 < queue.count else {
            player.pause(); return
        }
        currentIndex += 1
        loadCurrent()
    }

    func previous() {
        // If we're more than 3s in, restart the track instead of skipping back.
        if position > 3 {
            player.seek(to: .zero); return
        }
        guard currentIndex > 0 else { player.seek(to: .zero); return }
        currentIndex -= 1
        loadCurrent()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        statusObservation?.invalidate(); statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}

// MARK: - TVPlayerView

struct TVPlayerView: View {
    let context: TVPlayContext
    @StateObject private var model = TVPlayerModel()

    private var displayed: TVPlayable? {
        model.current ?? context.queue.first(where: { $0.id == context.startID })
    }

    var body: some View {
        ZStack {
            backdrop
            HStack(spacing: 70) {
                artwork
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayed?.title ?? "")
                            .font(.system(size: 46, weight: .bold))
                            .lineLimit(2)
                        Text((displayed?.artist.isEmpty ?? true) ? "Unknown Artist" : (displayed?.artist ?? ""))
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    progressBar
                    HStack(spacing: 44) {
                        controlButton("backward.fill") { model.previous() }
                        controlButton(model.isPlaying ? "pause.fill" : "play.fill", big: true) { model.togglePlayPause() }
                        controlButton("forward.fill") { model.next() }
                        if model.queue.count > 1 {
                            Text("\(model.currentIndex + 1) of \(model.queue.count)")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 12)
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
            }
            .padding(.horizontal, 110)
        }
        .onAppear { model.start(context: context) }
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var backdrop: some View {
        ZStack {
            Color.black
            TVAuthImage(url: displayed?.artworkURL, token: displayed?.authToken) { Color.black }
                .blur(radius: 90)
                .opacity(0.55)
            LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var artwork: some View {
        ZStack {
            TVAuthImage(url: displayed?.artworkURL, token: displayed?.authToken) {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "music.note").font(.system(size: 90)).foregroundStyle(.secondary)
                }
            }
            if model.isBuffering {
                ZStack {
                    Color.black.opacity(0.45)
                    VStack(spacing: 14) {
                        ProgressView().scaleEffect(1.6).tint(.white)
                        Text("Loading…").font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: 440, height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
    }

    private var progressBar: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
            HStack {
                Text(timeString(model.position))
                Spacer()
                Text(model.duration > 0 ? "-" + timeString(max(0, model.duration - model.position)) : "")
            }
            .font(.system(size: 22, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(width: 720)
    }

    private var fraction: Double {
        model.duration > 0 ? min(1, max(0, model.position / model.duration)) : 0
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func controlButton(_ symbol: String, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: big ? 46 : 32, weight: .semibold))
                .frame(width: big ? 120 : 96, height: big ? 120 : 96)
        }
    }
}
