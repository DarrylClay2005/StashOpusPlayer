import SwiftUI
import UIKit

extension NowPlayingView {

    // MARK: - Artwork display (switches on style)

    @ViewBuilder
    var artworkDisplay: some View {
        if let builtinStyle = selectedBuiltinStyle {
            builtinArtworkDisplay(for: builtinStyle)
        } else if let custom = selectedCustomStyle {
            CustomStyleArtworkView(song: player.currentSong, isPlaying: player.isPlaying, config: custom)
                .environmentObject(library)
        } else {
            KaleidoscopeBloomArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)
        }
    }

    @ViewBuilder
    func builtinArtworkDisplay(for style: NowPlayingArtworkStyle) -> some View {
        switch style {
        case .kaleidoscopeBloom:
            KaleidoscopeBloomArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .synthwaveHorizon:
            SynthwaveHorizonArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .equalizerCutout:
            EqualizerCutoutArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .liquidBlobFrame:
            LiquidBlobFrameArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .origamiFoldReveal:
            OrigamiFoldRevealArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .mosaicShatter:
            MosaicShatterArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .circuitPulse:
            CircuitPulseArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .radarSweep:
            RadarSweepArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .discoMirrorBall:
            DiscoMirrorBallArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .frostedIceCrystal:
            FrostedIceCrystalArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .bioluminescentTide:
            BioluminescentTideArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .cometOrbit:
            CometOrbitArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .paperLayersParallax:
            PaperLayersParallaxArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .chalkboardSketch:
            ChalkboardSketchArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .vinylCrateStack:
            VinylCrateStackArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .moltenGlassDrip:
            MoltenGlassDripArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .confettiBurstLoop:
            ConfettiBurstLoopArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .shadowPuppetSilhouette:
            ShadowPuppetSilhouetteArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .liveSpectrum:
            LiveSpectrumArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .vinylGrooveSpiral:
            VinylGrooveSpiralArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .cassetteReelSpin:
            CassetteReelSpinArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .auroraVeil:
            AuroraVeilArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .rippleReflection:
            RippleReflectionArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .neonSignFlicker:
            NeonSignFlickerArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)

        case .vhsScanGlitch:
            VHSScanGlitchArtworkView(song: player.currentSong, isPlaying: player.isPlaying)
                .environmentObject(library)
        }
    }
}
