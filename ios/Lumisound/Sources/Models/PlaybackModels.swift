import Foundation

enum RepeatMode: String, CaseIterable, Codable, Identifiable {
    case off
    case all
    case one

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }
}

struct PlaybackSnapshot: Codable, Equatable {
    static let currentVersion = 2

    var version: Int
    var currentSongID: Song.ID?
    var queue: [Song]
    var currentIndex: Int
    var position: TimeInterval
    var repeatMode: RepeatMode
    var shuffleEnabled: Bool

    init(
        version: Int = PlaybackSnapshot.currentVersion,
        currentSongID: Song.ID? = nil,
        queue: [Song],
        currentIndex: Int,
        position: TimeInterval,
        repeatMode: RepeatMode,
        shuffleEnabled: Bool
    ) {
        self.version = version
        self.currentSongID = currentSongID
        self.queue = queue
        self.currentIndex = currentIndex
        self.position = position
        self.repeatMode = repeatMode
        self.shuffleEnabled = shuffleEnabled
    }

    // CodingKeys to support missing `version` in older snapshots (default to 1).
    enum CodingKeys: String, CodingKey {
        case version, currentSongID, queue, currentIndex, position, repeatMode, shuffleEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? 1
        currentSongID = try? container.decode(Song.ID.self, forKey: .currentSongID)
        queue = try container.decode([Song].self, forKey: .queue)
        currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        position = try container.decode(TimeInterval.self, forKey: .position)
        repeatMode = try container.decode(RepeatMode.self, forKey: .repeatMode)
        shuffleEnabled = try container.decode(Bool.self, forKey: .shuffleEnabled)
    }
}

struct AudioSettings: Codable, Equatable {
    /// Upper bound for `volume`. Values above 1.0 (100%) drive the signal
    /// chain's gain stages hotter than unity — the output limiter in
    /// `AudioPlayerManager` prevents this from clipping.
    ///
    /// `AVAudioMixerNode.outputVolume` and `AVAudioPlayerNode.volume` are both
    /// hard-clamped to `0...1` by AVFoundation, so any boost above unity is
    /// realised separately via `AVAudioUnitEQ.globalGain` (in dB). `4.0` here
    /// corresponds to `20*log10(4) ≈ +12 dB` of boost headroom — the widest
    /// range the slider exposes.
    static let maxVolume: Float = 4.0

    /// Maximum boost, in dB, applied via `AVAudioUnitEQ.globalGain` when
    /// `volume` exceeds `1.0`. Matches `20*log10(maxVolume)`.
    static let maxBoostDB: Float = 12.0

    var volume: Float = 1.0
    var speed: Float = 1.0
    var pitchSemitones: Float = 0.0
    var equalizerEnabled: Bool = false
    var eqBands: [Float] = Array(repeating: 0, count: 10)
    var eqPreset: EQPreset = .flat
    var crossfadeEnabled: Bool = false
    var crossfadeDuration: TimeInterval = 2.0
    var gaplessEnabled: Bool = true
    var replayGainEnabled: Bool = false
    var bassBoostEnabled: Bool = false
    var bassBoostGain: Float = 0.0  // 0–15 dB extra on 32 Hz and 64 Hz bands
    var activeEffectID: String = "none"
}
