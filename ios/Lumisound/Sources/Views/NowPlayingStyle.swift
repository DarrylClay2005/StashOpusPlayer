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
    // Batch 2 of the visual overhaul — replaces retroCRT/spectrumWaveform/
    // cassetteTape/neonGlow/auraGlow/tiltCard.
    case circuitPulse
    case radarSweep
    case discoMirrorBall
    case frostedIceCrystal
    case bioluminescentTide
    case cometOrbit
    // Batch 3 (final) of the visual overhaul — replaces marquee/holographic/
    // ripple/popArt/starfield/stainedGlass. All 18 styles have now been
    // replaced at least once since the original set.
    case paperLayersParallax
    case chalkboardSketch
    case vinylCrateStack
    case moltenGlassDrip
    case confettiBurstLoop
    case shadowPuppetSilhouette

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kaleidoscopeBloom: return "Kaleidoscope Bloom"
        case .synthwaveHorizon:  return "Synthwave Horizon"
        case .equalizerCutout:   return "Equalizer Cutout"
        case .liquidBlobFrame:   return "Liquid Blob Frame"
        case .origamiFoldReveal: return "Origami Fold"
        case .mosaicShatter:     return "Mosaic Shatter"
        case .circuitPulse:      return "Circuit Pulse"
        case .radarSweep:        return "Radar Sweep"
        case .discoMirrorBall:   return "Disco Mirror Ball"
        case .frostedIceCrystal: return "Frosted Ice Crystal"
        case .bioluminescentTide: return "Bioluminescent Tide"
        case .cometOrbit:        return "Comet Orbit"
        case .paperLayersParallax:   return "Paper Layers"
        case .chalkboardSketch:      return "Chalkboard Sketch"
        case .vinylCrateStack:       return "Vinyl Crate Stack"
        case .moltenGlassDrip:       return "Molten Glass Drip"
        case .confettiBurstLoop:     return "Confetti Burst"
        case .shadowPuppetSilhouette: return "Shadow Puppet"
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
        case .circuitPulse:      return "cpu.fill"
        case .radarSweep:        return "dot.radiowaves.left.and.right"
        case .discoMirrorBall:   return "sparkles"
        case .frostedIceCrystal: return "snowflake"
        case .bioluminescentTide: return "water.waves"
        case .cometOrbit:        return "circle.dotted"
        case .paperLayersParallax:   return "square.stack.fill"
        case .chalkboardSketch:      return "pencil.and.outline"
        case .vinylCrateStack:       return "square.stack.3d.down.right.fill"
        case .moltenGlassDrip:       return "flame.fill"
        case .confettiBurstLoop:     return "party.popper.fill"
        case .shadowPuppetSilhouette: return "theatermasks.fill"
        }
    }
}
