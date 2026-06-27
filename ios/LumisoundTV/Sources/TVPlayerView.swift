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
    @Published var currentIndex = 0
    @Published private(set) var queue: [TVPlayable] = []

    let player = AVPlayer()
    private var endObserver: NSObjectProtocol?

    var current: TVPlayable? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }

    func start(context: TVPlayContext) {
        guard queue.isEmpty else { return }  // start once
        queue = context.queue
        currentIndex = queue.firstIndex(where: { $0.id == context.startID }) ?? 0
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        if endObserver == nil {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.next() }
            }
        }
        loadCurrent()
    }

    private func loadCurrent() {
        guard let item = current else { return }
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
        isPlaying = true
    }

    func togglePlayPause() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func next() {
        guard currentIndex + 1 < queue.count else {
            player.pause(); isPlaying = false; return
        }
        currentIndex += 1
        loadCurrent()
    }

    func previous() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        loadCurrent()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
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
            Color.black.ignoresSafeArea()
            backdrop
            VStack(spacing: 28) {
                artwork
                VStack(spacing: 6) {
                    Text(displayed?.title ?? "")
                        .font(.title2).bold().lineLimit(1)
                    Text((displayed?.artist.isEmpty ?? true) ? "Unknown Artist" : (displayed?.artist ?? ""))
                        .font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 50) {
                    controlButton("backward.fill") { model.previous() }
                    controlButton(model.isPlaying ? "pause.fill" : "play.fill", big: true) { model.togglePlayPause() }
                    controlButton("forward.fill") { model.next() }
                }
            }
            .padding(80)
        }
        .onAppear { model.start(context: context) }
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var backdrop: some View {
        TVAuthImage(url: displayed?.artworkURL, token: displayed?.authToken) { Color.black }
            .ignoresSafeArea()
            .blur(radius: 60)
            .overlay(Color.black.opacity(0.6).ignoresSafeArea())
    }

    @ViewBuilder private var artwork: some View {
        TVAuthImage(url: displayed?.artworkURL, token: displayed?.authToken) {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "music.note").font(.system(size: 80)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 380, height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func controlButton(_ symbol: String, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: big ? 44 : 30, weight: .semibold))
                .frame(width: big ? 110 : 90, height: big ? 110 : 90)
        }
    }
}
