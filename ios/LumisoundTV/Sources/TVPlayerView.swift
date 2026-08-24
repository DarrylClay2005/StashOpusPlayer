import SwiftUI
import AVFoundation

// MARK: - TVPlayContext (queue + where to start)

struct TVPlayContext: Hashable {
    let queue: [TVPlayable]
    let startID: String
}

enum TVRepeatMode {
    case off, all, one

    /// Cycles off → all → one → off, driven by a single button tap.
    var next: TVRepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var symbol: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
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
    @Published private(set) var isShuffled = false
    @Published var repeatMode: TVRepeatMode = .off
    @Published private(set) var sleepTimerEndDate: Date?

    let player = AVPlayer()
    /// Queue order before shuffling — restored when shuffle is toggled off.
    private var originalQueue: [TVPlayable] = []
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var sleepTimerTask: Task<Void, Never>?

    var current: TVPlayable? { queue.indices.contains(currentIndex) ? queue[currentIndex] : nil }

    func start(context: TVPlayContext) {
        guard queue.isEmpty else { return }  // start once
        queue = context.queue
        originalQueue = context.queue
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
                Task { @MainActor in self?.advanceOnEnd() }
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

    /// Manual "skip forward" — always advances (or stops at the end of a
    /// non-repeating queue), regardless of repeat mode. Repeat-one only
    /// affects what happens when a track ends on its own; see `advanceOnEnd`.
    func next() {
        guard currentIndex + 1 < queue.count else {
            if repeatMode == .all, !queue.isEmpty {
                currentIndex = 0
                loadCurrent()
            } else {
                player.pause()
            }
            return
        }
        currentIndex += 1
        loadCurrent()
    }

    /// Called when the current item finishes playing on its own.
    private func advanceOnEnd() {
        if repeatMode == .one {
            player.seek(to: .zero)
            player.play()
            return
        }
        next()
    }

    /// Jumps directly to a track elsewhere in the queue — used by the "Up
    /// Next" panel so picking a track doesn't require stepping through
    /// `next()` one at a time.
    func jump(to index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
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

    /// Removes a queued-up track. The currently-playing track can't be
    /// removed this way — skip to another track first.
    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        let removedID = queue[index].id
        queue.remove(at: index)
        if index < currentIndex { currentIndex -= 1 }
        originalQueue.removeAll { $0.id == removedID }
    }

    /// Shuffles everything except leaves the currently-playing track findable
    /// by id afterward (rather than resetting to index 0), so toggling
    /// shuffle mid-playback doesn't yank the listener to a different track.
    func toggleShuffle() {
        isShuffled.toggle()
        let currentID = current?.id
        queue = isShuffled ? originalQueue.shuffled() : originalQueue
        if let currentID {
            currentIndex = queue.firstIndex(where: { $0.id == currentID }) ?? 0
        }
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next
    }

    // MARK: Sleep timer

    func setSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimerEndDate = end
        sleepTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = end.timeIntervalSinceNow
                if remaining <= 0 {
                    self.player.pause()
                    self.sleepTimerEndDate = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndDate = nil
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
        cancelSleepTimer()
    }
}

// MARK: - TVPlayerView

struct TVPlayerView: View {
    let context: TVPlayContext
    @ObservedObject var client: TVBridgeClient
    let token: String
    @StateObject private var model = TVPlayerModel()
    @State private var showUpNext = false

    private var displayed: TVPlayable? {
        model.current ?? context.queue.first(where: { $0.id == context.startID })
    }

    var body: some View {
        ZStack {
            backdrop
            HStack(spacing: 70) {
                artwork
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(displayed?.title ?? "")
                                .font(.system(size: 46, weight: .bold))
                                .lineLimit(2)
                            if let songID = displayed?.favoriteSongID {
                                favoriteButton(songID: songID)
                            }
                        }
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
                    }
                    utilityRow
                }
                .frame(maxWidth: 760, alignment: .leading)
            }
            .padding(.horizontal, 110)

            if showUpNext {
                upNextPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear { model.start(context: context) }
        .onDisappear { model.stop() }
    }

    // MARK: Utility row (shuffle / repeat / sleep timer / up next)

    private var utilityRow: some View {
        HStack(spacing: 30) {
            toggleIconButton("shuffle", isOn: model.isShuffled) { model.toggleShuffle() }
            toggleIconButton(model.repeatMode.symbol, isOn: model.repeatMode != .off) { model.cycleRepeatMode() }
            sleepTimerMenu
            if model.queue.count > 1 {
                Text("\(model.currentIndex + 1) of \(model.queue.count)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showUpNext.toggle() }
                } label: {
                    Label("Up Next", systemImage: "list.bullet")
                }
            }
        }
    }

    private func toggleIconButton(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
    }

    private func favoriteButton(songID: String) -> some View {
        Button {
            Task {
                guard let track = client.library.first(where: { $0.id == songID }) else { return }
                await client.toggleFavorite(track: track, token: token)
            }
        } label: {
            Image(systemName: client.isFavorite(songID) ? "star.fill" : "star")
                .foregroundStyle(client.isFavorite(songID) ? Color.yellow : Color.secondary)
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            if model.sleepTimerEndDate != nil {
                Button(role: .destructive) { model.cancelSleepTimer() } label: {
                    Label("Cancel Sleep Timer", systemImage: "moon.slash")
                }
            }
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { model.setSleepTimer(minutes: minutes) }
            }
        } label: {
            Image(systemName: model.sleepTimerEndDate != nil ? "moon.fill" : "moon")
                .foregroundStyle(model.sleepTimerEndDate != nil ? Color.accentColor : Color.primary)
        }
    }

    // MARK: Up Next panel
    //
    // Slides over the artwork/transport rather than using `.sheet` — tvOS's
    // focus engine handles an in-place overlay more predictably than a modal
    // here, and it keeps the now-playing transport reachable underneath.

    private var upNextPanel: some View {
        HStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Up Next")
                        .font(.system(size: 30, weight: .bold))
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showUpNext = false }
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 50)
                .padding(.bottom, 20)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.queue.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 20) {
                                Button {
                                    model.jump(to: index)
                                } label: {
                                    HStack(spacing: 20) {
                                        Image(systemName: index == model.currentIndex ? "speaker.wave.2.fill" : "music.note")
                                            .foregroundStyle(index == model.currentIndex ? Color.accentColor : Color.secondary)
                                            .frame(width: 30)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title).font(.title3).lineLimit(1)
                                            Text(item.artist.isEmpty ? "Unknown Artist" : item.artist)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.leading, 40)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.card)

                                if index != model.currentIndex {
                                    Button {
                                        model.removeFromQueue(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.card)
                                    .padding(.trailing, 40)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .frame(width: 620, alignment: .top)
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.85))
        }
        .ignoresSafeArea()
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
