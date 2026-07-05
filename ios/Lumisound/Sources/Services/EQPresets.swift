import Foundation

enum EQPreset: String, CaseIterable, Codable, Identifiable {
    case flat = "Flat"
    case bassBoost = "Bass Boost"
    case trebleBoost = "Treble Boost"
    case vocal = "Vocal"
    case pop = "Pop"
    case electronic = "Electronic"
    case rock = "Rock"
    case classical = "Classical"
    case jazz = "Jazz"
    case hiphop = "Hip-Hop"
    case acoustic = "Acoustic"
    case custom = "Custom"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Suggests an EQ preset based on a track's tempo, for "Auto EQ" mode.
    /// Slower tracks lean toward presets that favor warmth/clarity over punch
    /// (Classical/Acoustic), mid-tempo toward Pop, and fast/high-energy tracks
    /// toward Electronic's boosted sub-bass and highs. Returns `nil` when `bpm`
    /// is unknown, leaving the current preset untouched.
    static func auto(forBPM bpm: Double?) -> EQPreset? {
        guard let bpm, bpm > 0 else { return nil }
        switch bpm {
        case ..<70:    return .classical
        case 70..<100: return .acoustic
        case 100..<130: return .pop
        default:       return .electronic
        }
    }

    /// Genre-aware Auto EQ: when a track carries a recognizable genre tag, map
    /// it directly to the matching tonal preset (a far stronger signal than
    /// tempo alone — a 90 BPM hip-hop track and a 90 BPM acoustic ballad want
    /// very different curves). Falls back to the tempo-based `auto(forBPM:)`
    /// when the genre is empty/unrecognized, so Auto EQ still adapts for
    /// untagged tracks. Returns `nil` only when neither signal is usable.
    static func auto(forBPM bpm: Double?, genre: String?) -> EQPreset? {
        if let preset = preset(forGenre: genre) {
            return preset
        }
        return auto(forBPM: bpm)
    }

    /// Maps a free-text genre tag (case/substring-insensitive) onto the closest
    /// built-in preset. Returns `nil` for empty or unrecognized genres.
    static func preset(forGenre genre: String?) -> EQPreset? {
        guard let raw = genre?.lowercased(), !raw.isEmpty else { return nil }
        // Ordered most-specific-first so e.g. "acoustic rock" matches Acoustic
        // before the broader "rock" rule.
        let rules: [(needles: [String], preset: EQPreset)] = [
            (["hip hop", "hip-hop", "hiphop", "rap", "trap", "drill"], .hiphop),
            (["classical", "orchestra", "symphony", "baroque", "opera"], .classical),
            (["acoustic", "folk", "singer-songwriter", "unplugged"], .acoustic),
            (["jazz", "blues", "swing", "bebop"], .jazz),
            (["edm", "electronic", "house", "techno", "trance", "dubstep", "dance", "drum and bass", "dnb"], .electronic),
            (["metal", "rock", "punk", "grunge", "alternative"], .rock),
            (["pop", "k-pop", "synthpop", "indie pop"], .pop),
            (["vocal", "a cappella", "acappella", "spoken"], .vocal),
        ]
        for rule in rules where rule.needles.contains(where: { raw.contains($0) }) {
            return rule.preset
        }
        return nil
    }

    // Returns 10 band gain values (dB) for frequencies:
    // 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
    //
    // Every genre-named curve here matches the equivalent preset in
    // `AudioEffectsService` exactly, so picking "Jazz" (say) from either the
    // Equalizer's preset picker or the Effects grid sounds the same —
    // previously several of these (Pop/Rock/Classical) were mechanically
    // converted from an unrelated 15-band system and didn't match at all.
    var bands: [Float] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

        case .bassBoost:
            // Punchy sub/bass lift with a small compensating dip through the
            // low-mids — matches AudioEffectsService.bassboost.
            return [8.0, 6.5, 4.0, 1.0, -1.0, -1.5, -1.0, 0, 0, 0]

        case .trebleBoost:
            // Slightly cut lows, open up the high end
            return [-2, -1, 0, 0, 0, 1, 2, 4, 5, 6]

        case .vocal:
            // Presence-focused — matches AudioEffectsService.vocalBoost.
            return [-2.0, -1.5, -1.0, 0.5, 2.0, 3.0, 2.5, 1.0, 0, -1.0]

        case .pop:
            // Bright, vocal-forward pop curve — matches AudioEffectsService.pop.
            return [0, 1.0, 1.5, 0.5, -1.0, -1.5, -0.5, 1.0, 2.5, 2.0]

        case .electronic:
            // Classic EDM "smiley" curve — matches AudioEffectsService.electronic.
            return [3.0, 2.0, 0, -1.0, -1.5, -1.0, 1.0, 2.5, 3.5, 3.0]

        case .rock:
            // The classic rock "V" curve — matches AudioEffectsService.rock.
            return [4.0, 2.5, -1.0, -2.0, -1.0, 1.0, 2.5, 3.0, 2.0, 1.5]

        case .classical:
            // Natural and accurate — matches AudioEffectsService.classical.
            return [1.0, 0.5, 0, 0, 0, 0, 0.5, 1.0, 1.5, 2.0]

        case .jazz:
            // Warm and smooth — matches AudioEffectsService.jazz.
            return [1.5, 1.0, 0.5, 0.5, 0, 0, 0.5, 1.0, 1.5, 1.0]

        case .hiphop:
            // Heavy 808 sub-bass with crisp highs — matches AudioEffectsService.hiphop.
            return [6.0, 4.5, 1.0, -1.5, -1.0, 0, 1.0, 2.0, 2.5, 1.5]

        case .acoustic:
            // Natural warmth with detail across the spectrum — matches
            // AudioEffectsService.acoustic.
            return [1.0, 1.0, 1.5, 1.0, 0.5, 0.5, 1.0, 1.0, 0.5, 1.0]

        case .custom:
            // User-defined values; this default is never applied over user edits
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}
