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
    // Distinctive styles, each its own visual concept
    case marquee
    case holographic
    case ripple
    case popArt
    case starfield
    case stainedGlass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vinylDisc:        return "Spin"
        case .albumArt:         return "Aurora Veil"
        case .polaroid:         return "Spotlight Stage"
        case .floatingCards:    return "Card Fan"
        case .minimalist:       return "Minimal Mono"
        case .glassmorphism:    return "Frost Panels"
        case .retroCRT:         return "Glitch Wave"
        case .spectrumWaveform: return "Spectrum Bars"
        case .cassetteTape:     return "Radial Spectrum"
        case .neonGlow:         return "Neon Trace"
        case .auraGlow:         return "Lava Lamp"
        case .tiltCard:         return "Depth Parallax"
        case .marquee:          return "Marquee Bulbs"
        case .holographic:      return "Foil Shimmer"
        case .ripple:           return "Halo Pulse"
        case .popArt:           return "Comic Halftone"
        case .starfield:        return "Cosmos"
        case .stainedGlass:     return "Prism Glass"
        }
    }

    var iconName: String {
        switch self {
        case .vinylDisc:        return "opticaldisc"
        case .albumArt:         return "sparkles"
        case .polaroid:         return "flashlight.on.fill"
        case .floatingCards:    return "square.stack.3d.up.fill"
        case .minimalist:       return "circle.lefthalf.filled"
        case .glassmorphism:    return "sparkles.rectangle.stack"
        case .retroCRT:         return "waveform.path"
        case .spectrumWaveform: return "chart.bar.fill"
        case .cassetteTape:     return "waveform.circle.fill"
        case .neonGlow:         return "bolt.fill"
        case .auraGlow:         return "drop.fill"
        case .tiltCard:         return "rotate.3d"
        case .marquee:          return "lightbulb.fill"
        case .holographic:      return "rainbow"
        case .ripple:           return "circle.circle.fill"
        case .popArt:           return "circle.hexagongrid.fill"
        case .starfield:        return "moon.stars.fill"
        case .stainedGlass:     return "rhombus.fill"
        }
    }
}
