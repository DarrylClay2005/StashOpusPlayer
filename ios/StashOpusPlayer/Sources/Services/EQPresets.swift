import Foundation

enum EQPreset: String, CaseIterable, Codable, Identifiable {
    case flat = "Flat"
    case bassBoost = "Bass Boost"
    case trebleBoost = "Treble Boost"
    case vocal = "Vocal"
    case electronic = "Electronic"
    case rock = "Rock"
    case classical = "Classical"
    case jazz = "Jazz"
    case hiphop = "Hip-Hop"
    case acoustic = "Acoustic"
    case custom = "Custom"

    var id: String { rawValue }
    var displayName: String { rawValue }

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

        case .electronic:
            // Strong sub-bass, slight mid scoop, boosted highs for air
            return [5, 4, 1, 0, -2, 0, 2, 3, 4, 5]

        case .rock:
            // Big low end, slight mid cut, sizzling high end
            return [4, 3, 2, 0, -1, -1, 0, 2, 3, 4]

        case .classical:
            // Gentle low and high shelf lift, flat mids — spacious
            return [3, 2, 0, 0, 0, 0, 0, 0, 2, 3]

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
