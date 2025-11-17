package com.stash.opusplayer.player.domain.models

/**
 * Audio Effects Configuration
 * Comprehensive configuration for all audio processing effects
 */
data class AudioEffects(
    // Equalizer settings
    val equalizerEnabled: Boolean = false,
    val equalizerPreset: Int = 0,
    val equalizerBands: FloatArray = FloatArray(10) { 0f },
    
    // Bass boost
    val bassBoostEnabled: Boolean = false,
    val bassBoostStrength: Int = 0, // 0-1000
    
    // Virtualizer (surround sound effect)
    val virtualizerEnabled: Boolean = false,
    val virtualizerStrength: Int = 0, // 0-1000
    
    // Reverb
    val reverbEnabled: Boolean = false,
    val reverbPreset: Int = 0,
    
    // Compression/Dynamics
    val compressionEnabled: Boolean = false,
    val compressionThreshold: Float = -12f, // dB
    val compressionRatio: Float = 4f, // ratio
    val compressionAttack: Float = 5f, // ms
    val compressionRelease: Float = 50f, // ms
    val compressionMakeupGain: Float = 0f, // dB
    
    // Stereo enhancement
    val stereoWidthEnabled: Boolean = false,
    val stereoWidth: Float = 1f, // 0.0 to 2.0
    
    // Crossfeed (headphone)
    val crossfeedEnabled: Boolean = false,
    val crossfeedAmount: Float = 0.5f, // 0.0 to 1.0
    
    // Tube warmth/saturation
    val tubeWarmthEnabled: Boolean = false,
    val tubeWarmth: Float = 0f, // 0.0 to 1.0
    
    // Loudness normalization
    val loudnessNormalizationEnabled: Boolean = false,
    val targetLufs: Float = -16f, // LUFS target
    
    // 8D/Spatial audio
    val spatialAudioEnabled: Boolean = false,
    val spatialAudioIntensity: Float = 0.5f,
    
    // Advanced DSP
    val dspEnabled: Boolean = false,
    val dspProfile: String = "None"
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as AudioEffects

        if (equalizerEnabled != other.equalizerEnabled) return false
        if (equalizerPreset != other.equalizerPreset) return false
        if (!equalizerBands.contentEquals(other.equalizerBands)) return false
        if (bassBoostEnabled != other.bassBoostEnabled) return false
        if (bassBoostStrength != other.bassBoostStrength) return false
        if (virtualizerEnabled != other.virtualizerEnabled) return false
        if (virtualizerStrength != other.virtualizerStrength) return false
        if (reverbEnabled != other.reverbEnabled) return false
        if (reverbPreset != other.reverbPreset) return false
        if (compressionEnabled != other.compressionEnabled) return false
        if (compressionThreshold != other.compressionThreshold) return false
        if (compressionRatio != other.compressionRatio) return false
        if (compressionAttack != other.compressionAttack) return false
        if (compressionRelease != other.compressionRelease) return false
        if (compressionMakeupGain != other.compressionMakeupGain) return false
        if (stereoWidthEnabled != other.stereoWidthEnabled) return false
        if (stereoWidth != other.stereoWidth) return false
        if (crossfeedEnabled != other.crossfeedEnabled) return false
        if (crossfeedAmount != other.crossfeedAmount) return false
        if (tubeWarmthEnabled != other.tubeWarmthEnabled) return false
        if (tubeWarmth != other.tubeWarmth) return false
        if (loudnessNormalizationEnabled != other.loudnessNormalizationEnabled) return false
        if (targetLufs != other.targetLufs) return false
        if (spatialAudioEnabled != other.spatialAudioEnabled) return false
        if (spatialAudioIntensity != other.spatialAudioIntensity) return false
        if (dspEnabled != other.dspEnabled) return false
        if (dspProfile != other.dspProfile) return false

        return true
    }

    override fun hashCode(): Int {
        var result = equalizerEnabled.hashCode()
        result = 31 * result + equalizerPreset
        result = 31 * result + equalizerBands.contentHashCode()
        result = 31 * result + bassBoostEnabled.hashCode()
        result = 31 * result + bassBoostStrength
        result = 31 * result + virtualizerEnabled.hashCode()
        result = 31 * result + virtualizerStrength
        result = 31 * result + reverbEnabled.hashCode()
        result = 31 * result + reverbPreset
        result = 31 * result + compressionEnabled.hashCode()
        result = 31 * result + compressionThreshold.hashCode()
        result = 31 * result + compressionRatio.hashCode()
        result = 31 * result + compressionAttack.hashCode()
        result = 31 * result + compressionRelease.hashCode()
        result = 31 * result + compressionMakeupGain.hashCode()
        result = 31 * result + stereoWidthEnabled.hashCode()
        result = 31 * result + stereoWidth.hashCode()
        result = 31 * result + crossfeedEnabled.hashCode()
        result = 31 * result + crossfeedAmount.hashCode()
        result = 31 * result + tubeWarmthEnabled.hashCode()
        result = 31 * result + tubeWarmth.hashCode()
        result = 31 * result + loudnessNormalizationEnabled.hashCode()
        result = 31 * result + targetLufs.hashCode()
        result = 31 * result + spatialAudioEnabled.hashCode()
        result = 31 * result + spatialAudioIntensity.hashCode()
        result = 31 * result + dspEnabled.hashCode()
        result = 31 * result + dspProfile.hashCode()
        return result
    }
}
