import Foundation
import Combine

/// "Needle Drop" — a music-guessing mini-game built entirely from the
/// user's own library: play a short random clip from a random deep-enough
/// cut into a track, offer 4 title/artist choices (1 real, 3 decoys drawn
/// from the same library), and see how long a correct-guess streak you can
/// build. Fully on-device, no server/account involvement — a personal
/// high-score table via UserDefaults, same lightweight persistence style
/// as `PlayHistoryStore`.
///
/// Deliberately reuses the main `AudioPlayerManager` rather than spinning
/// up a second player instance — `startSession`/`endSession` snapshot and
/// restore whatever was queued before the game started, so playing a round
/// never permanently disrupts what the user was actually listening to.
enum NeedleDropRoundState: Equatable {
    case idle
    case playing
    case revealed(correct: Bool)
}

@MainActor
final class NeedleDropService: ObservableObject {
    private static let bestStreakKey = "needleDrop.bestStreak"
    private static let totalCorrectKey = "needleDrop.totalCorrect"
    private static let totalRoundsKey = "needleDrop.totalRounds"

    /// How long each clip plays before auto-pausing if the player hasn't guessed yet.
    private let clipDuration: TimeInterval = 4
    /// Skips the very start/end of a track so the clip is a genuine "guess from
    /// the middle" moment rather than a giveaway intro or fade-out.
    private let edgeMargin: TimeInterval = 6

    @Published private(set) var state: NeedleDropRoundState = .idle
    @Published private(set) var currentStreak = 0
    @Published private(set) var bestStreak: Int
    @Published private(set) var totalCorrect: Int
    @Published private(set) var totalRounds: Int
    @Published private(set) var options: [Song] = []
    @Published private(set) var mysterySong: Song?

    weak var player: AudioPlayerManager?

    private var savedQueue: [Song] = []
    private var savedIndex = 0
    private var savedWasPlaying = false
    private var hasSavedState = false
    private var clipTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        bestStreak = defaults.integer(forKey: Self.bestStreakKey)
        totalCorrect = defaults.integer(forKey: Self.totalCorrectKey)
        totalRounds = defaults.integer(forKey: Self.totalRoundsKey)
    }

    /// Snapshots whatever is currently queued/playing so the game can freely
    /// take over the player, then starts the first round.
    func startSession(library: LibraryManager) {
        guard let player, !hasSavedState else { return }
        savedQueue = player.queue
        savedIndex = player.currentIndex
        savedWasPlaying = player.isPlaying
        hasSavedState = true
        currentStreak = 0
        nextRound(library: library)
    }

    /// Restores the pre-game queue/playback state — called when the user
    /// leaves the Needle Drop screen.
    func endSession() {
        clipTask?.cancel()
        clipTask = nil
        guard hasSavedState else { return }
        player?.pause()
        if let player, !savedQueue.isEmpty {
            player.setQueue(savedQueue, startIndex: savedIndex, autoplay: savedWasPlaying)
        }
        hasSavedState = false
        state = .idle
        mysterySong = nil
        options = []
    }

    /// Picks a new mystery track + 3 decoys from the library, starts it
    /// playing from a random point, and auto-pauses after `clipDuration`
    /// if the player hasn't guessed by then.
    func nextRound(library: LibraryManager) {
        clipTask?.cancel()
        // Long enough to have a real "middle" to drop the needle into, once
        // both edge margins are excluded.
        let eligible = library.allSongs.filter { $0.duration > edgeMargin * 2 + clipDuration }
        guard eligible.count >= 4, let player else {
            state = .idle
            return
        }
        let answer = eligible.randomElement()!
        var decoys = eligible.filter { $0.id != answer.id }
        decoys.shuffle()
        options = ([answer] + decoys.prefix(3)).shuffled()
        mysterySong = answer
        state = .playing

        let latestStart = max(edgeMargin, answer.duration - edgeMargin - clipDuration)
        let clipStart = TimeInterval.random(in: edgeMargin...latestStart)
        player.setQueue([answer], startIndex: 0, autoplay: true)

        let clipNanoseconds = UInt64(clipDuration * 1_000_000_000)
        clipTask = Task { [weak self, weak player] in
            // Give AVFoundation a beat to actually start playback before
            // seeking into it — seeking immediately after `setQueue` can
            // land before the player has anything loaded to seek within.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            player?.seek(to: clipStart)
            try? await Task.sleep(nanoseconds: clipNanoseconds)
            guard !Task.isCancelled, let self, case .playing = self.state else { return }
            player?.pause()
        }
    }

    /// Records a guess (correct or not), stops the clip, and reveals the answer.
    func submitGuess(_ song: Song) {
        guard case .playing = state, let mysterySong else { return }
        clipTask?.cancel()
        clipTask = nil
        player?.pause()

        let correct = song.id == mysterySong.id
        state = .revealed(correct: correct)
        totalRounds += 1
        if correct {
            currentStreak += 1
            totalCorrect += 1
            if currentStreak > bestStreak {
                bestStreak = currentStreak
                UserDefaults.standard.set(bestStreak, forKey: Self.bestStreakKey)
            }
        } else {
            currentStreak = 0
        }
        UserDefaults.standard.set(totalCorrect, forKey: Self.totalCorrectKey)
        UserDefaults.standard.set(totalRounds, forKey: Self.totalRoundsKey)
    }

    /// Replays the same clip from the same start point — doesn't count as a new round.
    func replayClip() {
        guard case .playing = state, let player, let mysterySong else { return }
        let latestStart = max(edgeMargin, mysterySong.duration - edgeMargin - clipDuration)
        player.seek(to: min(player.position, latestStart))
        if !player.isPlaying { player.togglePlayPause() }
    }
}
