import SwiftUI

// MARK: - NowPlayingArtworkStyle

enum NowPlayingArtworkStyle: String, CaseIterable, Identifiable {
    // Batch 1 of a full visual overhaul (2026-07) — replaces the original
    // vinylDisc/albumArt/polaroid/floatingCards/minimalist/glassmorphism
    // styles with entirely new concepts + animations. Existing users' saved
    // style preference (persisted by rawValue) won't match any new case and
    // falls back to the default — expected, since the old styles no longer
    // exist in any form.
    case kaleidoscopeBloom
    case synthwaveHorizon
    case equalizerCutout
    case liquidBlobFrame
    case origamiFoldReveal
    case mosaicShatter
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
        case .kaleidoscopeBloom: return "Kaleidoscope Bloom"
        case .synthwaveHorizon:  return "Synthwave Horizon"
        case .equalizerCutout:   return "Equalizer Cutout"
        case .liquidBlobFrame:   return "Liquid Blob Frame"
        case .origamiFoldReveal: return "Origami Fold"
        case .mosaicShatter:     return "Mosaic Shatter"
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
        case .kaleidoscopeBloom: return "hexagon.fill"
        case .synthwaveHorizon:  return "sun.horizon.fill"
        case .equalizerCutout:   return "chart.bar.fill"
        case .liquidBlobFrame:   return "drop.circle.fill"
        case .origamiFoldReveal: return "triangle.fill"
        case .mosaicShatter:     return "square.grid.3x3.fill"
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
