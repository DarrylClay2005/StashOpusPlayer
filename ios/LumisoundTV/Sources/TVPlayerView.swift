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
    @Published private(set) var lyrics: [TVLyricLine] = []
    @Published private(set) var isLoadingLyrics = false
    @Published var crossfadeEnabled: Bool = UserDefaults.standard.bool(forKey: "tv.player.crossfadeEnabled") {
        didSet { UserDefaults.standard.set(crossfadeEnabled, forKey: "tv.player.crossfadeEnabled") }
    }

    // MARK: Dual-player crossfade
    //
    // Two fixed AVPlayer instances rather than one — crossfading means the
    // outgoing track's player and the incoming track's player must both be
    // audible and advancing at once for `crossfadeDuration` seconds, which a
    // single `replaceCurrentItem` swap can't do. `player` always means
    // "whichever one is currently the audible/active track"; observers (time/
    // status/end) are attached to BOTH once, each self-filtering to only act
    // when it's the currently-active instance — simpler and safer than tearing
    // down and reattaching observers every time the active player changes.
    private let playerA = AVPlayer()
    private let playerB = AVPlayer()
    private var activeIsA = true
    var player: AVPlayer { activeIsA ? playerA : playerB }
    private var inactivePlayer: AVPlayer { activeIsA ? playerB : playerA }
    private let crossfadeDuration: TimeInterval = 6
    private var crossfadeTask: Task<Void, Never>?
    private var hasCrossfadedForCurrentTrack = false

    /// Queue order before shuffling — restored when shuffle is toggled off.
    private var originalQueue: [TVPlayable] = []
    private var endObservers: [NSObjectProtocol] = []
    private var timeObservers: [(AVPlayer, Any)] = []
    private var statusObservations: [NSKeyValueObservation] = []
    private var sleepTimerTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?

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
        guard endObservers.isEmpty else { return }  // set up once, on both players

        for p in [playerA, playerB] {
            // Only reacts when `p` is the currently-active player AND the item
            // that ended is still that player's current item — guards against
            // a stale notification from a player that's since been reused/
            // reset (e.g. a cancelled crossfade's incoming player).
            let endObs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
            ) { [weak self, weak p] note in
                Task { @MainActor in
                    guard let self, let p, self.player === p,
                          let endedItem = note.object as? AVPlayerItem, endedItem === p.currentItem
                    else { return }
                    self.handleNaturalEnd()
                }
            }
            endObservers.append(endObs)

            // Drives the scrubber + elapsed/remaining time, and the crossfade trigger.
            let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
            let timeObs = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak p] time in
                Task { @MainActor in
                    guard let self, let p, self.player === p else { return }
                    self.position = time.seconds.isFinite ? time.seconds : 0
                    if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 {
                        self.duration = d
                    }
                    self.checkCrossfadeTrigger()
                }
            }
            timeObservers.append((p, timeObs))

            // Keeps play/pause + the loading spinner in sync with real playback.
            let statusObs = p.observe(\.timeControlStatus, options: [.new]) { [weak self, weak p] observed, _ in
                Task { @MainActor in
                    guard let self, let p, self.player === p else { return }
                    self.isPlaying = observed.timeControlStatus == .playing
                    self.isBuffering = observed.timeControlStatus == .waitingToPlayAtSpecifiedRate
                }
            }
            statusObservations.append(statusObs)
        }
    }

    private func asset(for item: TVPlayable) -> AVURLAsset {
        if let token = item.authToken {
            return AVURLAsset(url: item.streamURL, options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]
            ])
        }
        return AVURLAsset(url: item.streamURL)
    }

    private func loadCurrent() {
        guard let item = current else { return }
        cancelCrossfade()
        position = 0
        duration = 0
        isBuffering = true
        player.volume = 1
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset(for: item)))
        player.play()
        loadLyrics(for: item)
    }

    // MARK: Crossfade

    /// Only the natural end of the *active* player's item reaches here — if
    /// a crossfade already claimed this transition (`hasCrossfadedForCurrentTrack`),
    /// `completeCrossfade` handles advancing instead, so this no-ops to avoid
    /// double-advancing.
    private func handleNaturalEnd() {
        guard !hasCrossfadedForCurrentTrack else { return }
        advanceOnEnd()
    }

    private func nextIndexForCrossfade() -> Int? {
        guard crossfadeEnabled, queue.count > 1, repeatMode != .one else { return nil }
        if currentIndex + 1 < queue.count { return currentIndex + 1 }
        if repeatMode == .all { return 0 }
        return nil
    }

    private func checkCrossfadeTrigger() {
        guard !hasCrossfadedForCurrentTrack, duration > crossfadeDuration,
              duration - position <= crossfadeDuration,
              nextIndexForCrossfade() != nil
        else { return }
        hasCrossfadedForCurrentTrack = true
        beginCrossfade()
    }

    private func beginCrossfade() {
        guard let nextIndex = nextIndexForCrossfade(), queue.indices.contains(nextIndex) else { return }
        let nextItem = queue[nextIndex]
        let outgoing = player
        let incoming = inactivePlayer

        incoming.pause()
        incoming.volume = 0
        incoming.replaceCurrentItem(with: AVPlayerItem(asset: asset(for: nextItem)))
        incoming.play()

        let steps = 30
        let stepNanoseconds = UInt64(crossfadeDuration / Double(steps) * 1_000_000_000)
        crossfadeTask = Task { [weak self] in
            for i in 0...steps {
                guard !Task.isCancelled else { return }
                let t = Double(i) / Double(steps)
                // Equal-power curve so the perceived combined loudness stays
                // roughly constant through the fade, rather than dipping in
                // the middle the way a plain linear crossfade would.
                outgoing.volume = Float(cos(t * .pi / 2))
                incoming.volume = Float(sin(t * .pi / 2))
                try? await Task.sleep(nanoseconds: stepNanoseconds)
            }
            guard !Task.isCancelled, let self else { return }
            self.completeCrossfade(to: nextIndex)
        }
    }

    private func completeCrossfade(to index: Int) {
        let finishedOutgoing = player
        activeIsA.toggle()
        currentIndex = index
        position = 0
        duration = 0
        isBuffering = false
        hasCrossfadedForCurrentTrack = false
        crossfadeTask = nil
        player.volume = 1
        finishedOutgoing.pause()
        finishedOutgoing.replaceCurrentItem(with: nil)
        loadLyrics(for: queue[index])
    }

    /// Stops and silences an in-flight crossfade (the not-yet-promoted
    /// incoming player is fully paused/cleared, not just volume-reset —
    /// leaving it playing at any nonzero volume would mean two tracks
    /// audible at once until something else resolved it). Safe to call any
    /// time; a no-op when no crossfade is in flight.
    private func cancelCrossfade() {
        guard crossfadeTask != nil else { return }
        crossfadeTask?.cancel()
        crossfadeTask = nil
        hasCrossfadedForCurrentTrack = false
        player.volume = 1
        inactivePlayer.pause()
        inactivePlayer.replaceCurrentItem(with: nil)
        inactivePlayer.volume = 1
    }

    // MARK: Lyrics

    /// Waits briefly for the asset's real duration to load (used to reject a
    /// same-titled-but-wrong recording/song — see TVLyricsService) before
    /// fetching, falling back to an undisambiguated search if it takes too
    /// long. Re-checks `current?.id == item.id` after every suspension point
    /// since the user may have skipped tracks while this was waiting/in flight.
    private func loadLyrics(for item: TVPlayable) {
        lyricsTask?.cancel()
        lyrics = []
        isLoadingLyrics = true
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            var waited = 0.0
            while self.duration <= 0, waited < 5, !Task.isCancelled, self.current?.id == item.id {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 0.2
            }
            guard !Task.isCancelled, self.current?.id == item.id else { return }
            let fetched = await TVLyricsService.fetch(title: item.title, artist: item.artist, duration: self.duration)
            guard !Task.isCancelled, self.current?.id == item.id else { return }
            self.lyrics = fetched ?? []
            self.isLoadingLyrics = false
        }
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    /// Manual "skip forward" — always advances (or stops at the end of a
    /// non-repeating queue), regardless of repeat mode. Repeat-one only
    /// affects what happens when a track ends on its own; see `advanceOnEnd`.
    func next() {
        cancelCrossfade()
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
        cancelCrossfade()
        currentIndex = index
        loadCurrent()
    }

    func previous() {
        cancelCrossfade()
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
        // A removal could invalidate the index an in-flight crossfade is
        // ramping toward — simplest safe response is to cancel it; the
        // transition falls back to an instant swap when this track ends.
        cancelCrossfade()
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
        crossfadeTask?.cancel()
        crossfadeTask = nil
        for p in [playerA, playerB] {
            p.pause()
            p.replaceCurrentItem(with: nil)
        }
        for (p, observer) in timeObservers { p.removeTimeObserver(observer) }
        timeObservers.removeAll()
        statusObservations.forEach { $0.invalidate() }
        statusObservations.removeAll()
        endObservers.forEach { NotificationCenter.default.removeObserver($0) }
        endObservers.removeAll()
        cancelSleepTimer()
        lyricsTask?.cancel()
        lyricsTask = nil
    }
}

// MARK: - TVPlayerView

private enum TVSidePanel { case none, upNext, lyrics }

struct TVPlayerView: View {
    let context: TVPlayContext
    @ObservedObject var client: TVBridgeClient
    let token: String
    @StateObject private var model = TVPlayerModel()
    @State private var sidePanel: TVSidePanel = .none
    @State private var showSleepTimerSheet = false
    @State private var showArtworkStyleSheet = false
    @AppStorage("tv.nowPlaying.artworkStyle") private var artworkStyleRaw = TVArtworkStyle.classic.rawValue

    private var artworkStyle: TVArtworkStyle { TVArtworkStyle(rawValue: artworkStyleRaw) ?? .classic }

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

            if sidePanel == .upNext {
                upNextPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if sidePanel == .lyrics {
                TVLyricsPanel(
                    lines: model.lyrics,
                    currentPosition: model.position,
                    isPlaying: model.isPlaying,
                    isLoading: model.isLoadingLyrics,
                    onClose: { withAnimation(.easeInOut(duration: 0.25)) { sidePanel = .none } }
                )
                .transition(.opacity)
            }
        }
        .onAppear { model.start(context: context) }
        .onDisappear { model.stop() }
    }

    private func togglePanel(_ panel: TVSidePanel) {
        withAnimation(.easeInOut(duration: 0.25)) {
            sidePanel = sidePanel == panel ? .none : panel
        }
    }

    // MARK: Utility row (shuffle / repeat / sleep timer / lyrics / artwork style / up next)

    private var utilityRow: some View {
        HStack(spacing: 30) {
            toggleIconButton("shuffle", isOn: model.isShuffled) { model.toggleShuffle() }
            toggleIconButton(model.repeatMode.symbol, isOn: model.repeatMode != .off) { model.cycleRepeatMode() }
            toggleIconButton("arrow.triangle.merge", isOn: model.crossfadeEnabled) { model.crossfadeEnabled.toggle() }
            sleepTimerMenu
            toggleIconButton("quote.bubble", isOn: sidePanel == .lyrics) { togglePanel(.lyrics) }
            artworkStyleMenu
            if model.queue.count > 1 {
                Text("\(model.currentIndex + 1) of \(model.queue.count)")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    togglePanel(.upNext)
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
        Button {
            showSleepTimerSheet = true
        } label: {
            Image(systemName: model.sleepTimerEndDate != nil ? "moon.fill" : "moon")
                .foregroundStyle(model.sleepTimerEndDate != nil ? Color.accentColor : Color.primary)
        }
        .sheet(isPresented: $showSleepTimerSheet) {
            TVSleepTimerSheet(hasActiveTimer: model.sleepTimerEndDate != nil) { minutes in
                if let minutes {
                    model.setSleepTimer(minutes: minutes)
                } else {
                    model.cancelSleepTimer()
                }
            }
        }
    }

    private var artworkStyleMenu: some View {
        Button {
            showArtworkStyleSheet = true
        } label: {
            Image(systemName: "paintpalette")
                .foregroundStyle(artworkStyle == .classic ? Color.primary : Color.accentColor)
        }
        .sheet(isPresented: $showArtworkStyleSheet) {
            TVArtworkStyleSheet(current: artworkStyle) { style in
                artworkStyleRaw = style.rawValue
            }
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
                        withAnimation(.easeInOut(duration: 0.25)) { sidePanel = .none }
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
            switch artworkStyle {
            case .classic:
                classicArtwork
            case .circuitPulse:
                TVCircuitPulseArtworkView(artworkURL: displayed?.artworkURL, authToken: displayed?.authToken, isPlaying: model.isPlaying)
            case .radarSweep:
                TVRadarSweepArtworkView(artworkURL: displayed?.artworkURL, authToken: displayed?.authToken, isPlaying: model.isPlaying)
            }

            if model.isBuffering {
                ZStack {
                    Color.black.opacity(0.45)
                    VStack(spacing: 14) {
                        ProgressView().scaleEffect(1.6).tint(.white)
                        Text("Loading…").font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                    }
                }
                .frame(width: 440, height: 440)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .frame(width: 440, height: 440)
    }

    private var classicArtwork: some View {
        TVAuthImage(url: displayed?.artworkURL, token: displayed?.authToken) {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "music.note").font(.system(size: 90)).foregroundStyle(.secondary)
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

// MARK: - Sleep timer / artwork style pickers
//
// `Menu` needs tvOS 17 — this project's deployment target is tvOS 16 (see
// project.yml) — so these use the same `.sheet` + `List` picker pattern
// already proven elsewhere (TVAddToPlaylistSheet, TVPlaylistNameSheet)
// instead.

private struct TVSleepTimerSheet: View {
    let hasActiveTimer: Bool
    /// `nil` selection means "cancel the active timer".
    let onSelect: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if hasActiveTimer {
                    Button(role: .destructive) {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("Cancel Sleep Timer", systemImage: "moon.slash")
                    }
                }
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        onSelect(minutes)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Sleep Timer")
        }
    }
}

private struct TVArtworkStyleSheet: View {
    let current: TVArtworkStyle
    let onSelect: (TVArtworkStyle) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(TVArtworkStyle.allCases) { style in
                    Button {
                        onSelect(style)
                        dismiss()
                    } label: {
                        HStack {
                            Text(style.displayName)
                            if style == current {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Artwork Style")
        }
    }
}
