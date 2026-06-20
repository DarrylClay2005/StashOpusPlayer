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
    var bands: [Float] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

        case .bassBoost:
            // Emphasise sub-bass and bass, slightly cut high presence
            return [6, 5, 3, 1, 0, 0, 0, -1, -1, -2]

        case .trebleBoost:
            // Slightly cut lows, open up the high end
            return [-2, -1, 0, 0, 0, 1, 2, 4, 5, 6]

        case .vocal:
            // Scoop lows, presence peak in the 500 Hz–2 kHz vocal range
            return [-2, -1, 0, 2, 4, 4, 3, 2, 1, -1]

        case .pop:
            // Derived from bot 15-band definition (gws.py):
            // Flat sub, boosted low-mid punch, slight upper-mid dip, airy highs
            return [0.0, 2.4, 2.7, 1.2, -0.3, -1.2, -0.6, 0.0, 1.8, 1.2]

        case .electronic:
            // Strong sub-bass, slight mid scoop, boosted highs for air
            return [5, 4, 1, 0, -2, 0, 2, 3, 4, 5]

        case .rock:
            // Derived from bot 15-band definition (gws.py):
            // Big sub/low boost, mid scoop, presence peak at 1–4 kHz
            return [3.3, 1.2, -1.5, -1.2, 0.6, 3.9, 3.6, 2.4, 0.9, 0.0]

        case .classical:
            // Derived from bot 15-band definition (gws.py):
            // Gentle sub shelf, flat-to-slight dip in mids, rising high-end air
            return [1.2, 0.6, -0.3, -0.6, -0.6, -0.6, 0.0, 0.6, 1.5, 2.4]

        case .jazz:
            // Warm low end, slight upper-mid dip, open highs
            return [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]

        case .hiphop:
            // Heavy sub and bass, slight upper presence boost
            return [5, 4, 1, 3, -1, -1, 0, -1, 1, 2]

        case .acoustic:
            // Natural warmth with detail across the spectrum
            return [3, 2, 1, 2, 1, 0, 0, 1, 2, 2]

        case .custom:
            // User-defined values; this default is never applied over user edits
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        }
    }
}
