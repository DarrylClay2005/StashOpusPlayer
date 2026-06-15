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
    case auraGlow
    case tiltCard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vinylDisc:        return "Vinyl Disc"
        case .albumArt:         return "Album Art"
        case .polaroid:         return "Origami"
        case .floatingCards:    return "Floating Cards"
        case .minimalist:       return "Editorial"
        case .glassmorphism:    return "Glassmorphism"
        case .retroCRT:         return "Retro CRT"
        case .spectrumWaveform: return "Pulse Field"
        case .cassetteTape:     return "Ticket Stub"
        case .neonGlow:         return "Prism Beams"
        case .auraGlow:         return "Liquid Aura"
        case .tiltCard:         return "Tilt Card"
        }
    }

    var iconName: String {
        switch self {
        case .vinylDisc:        return "opticaldisc"
        case .albumArt:         return "photo"
        case .polaroid:         return "square.on.square"
        case .floatingCards:    return "rectangle.on.rectangle"
        case .minimalist:       return "newspaper"
        case .glassmorphism:    return "sparkles.rectangle.stack"
        case .retroCRT:         return "tv.inset.filled"
        case .spectrumWaveform: return "circle.grid.3x3.fill"
        case .cassetteTape:     return "ticket.fill"
        case .neonGlow:         return "sun.max.fill"
        case .auraGlow:         return "drop.fill"
        case .tiltCard:         return "rotate.3d"
        }
    }
}
