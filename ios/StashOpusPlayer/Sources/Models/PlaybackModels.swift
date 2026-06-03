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
    var currentSongID: Song.ID?
    var queue: [Song]
    var currentIndex: Int
    var position: TimeInterval
    var repeatMode: RepeatMode
    var shuffleEnabled: Bool
}

struct AudioSettings: Codable, Equatable {
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
}
