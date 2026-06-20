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
    // New modernized styles
    case depthParallax
    case frostedStack
    case haloRing
    case spotlight
    case mirrorWall
    case waveBorder

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
        case .depthParallax:    return "Depth Parallax"
        case .frostedStack:     return "Frosted Stack"
        case .haloRing:         return "Halo Ring"
        case .spotlight:        return "Spotlight"
        case .mirrorWall:       return "Mirror Wall"
        case .waveBorder:       return "Wave Border"
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
        case .depthParallax:    return "square.3.layers.3d"
        case .frostedStack:     return "square.stack.3d.up.fill"
        case .haloRing:         return "circle.circle.fill"
        case .spotlight:        return "lightbulb.max.fill"
        case .mirrorWall:       return "rectangle.fill.on.rectangle.fill"
        case .waveBorder:       return "waveform.circle.fill"
        }
    }
}
