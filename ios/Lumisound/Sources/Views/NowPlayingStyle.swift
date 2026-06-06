import SwiftUI

// MARK: - NowPlayingArtworkStyle

enum NowPlayingArtworkStyle: String, CaseIterable, Identifiable {
    case vinylDisc
    case albumArt
    case polaroid
    case floatingCards
    case minimalist
    case glassmorphism
    case retroCRT
    case spectrumWaveform
    case cassetteTape
    case neonGlow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vinylDisc:        return "Vinyl Disc"
        case .albumArt:         return "Album Art"
        case .polaroid:         return "Polaroid"
        case .floatingCards:    return "Floating Cards"
        case .minimalist:       return "Minimalist"
        case .glassmorphism:    return "Glassmorphism"
        case .retroCRT:         return "Retro CRT"
        case .spectrumWaveform: return "Spectrum"
        case .cassetteTape:     return "Cassette"
        case .neonGlow:         return "Neon Glow"
        }
    }

    var iconName: String {
        switch self {
        case .vinylDisc:        return "opticaldisc"
        case .albumArt:         return "photo"
        case .polaroid:         return "camera.on.rectangle"
        case .floatingCards:    return "rectangle.on.rectangle"
        case .minimalist:       return "square"
        case .glassmorphism:    return "sparkles.rectangle.stack"
        case .retroCRT:         return "tv.inset.filled"
        case .spectrumWaveform: return "waveform.path.ecg"
        case .cassetteTape:     return "recordingtape"
        case .neonGlow:         return "sparkles"
        }
    }
}
