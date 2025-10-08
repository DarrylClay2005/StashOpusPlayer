package com.stash.opusplayer.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.sqrt

class EnhancedEqualizerViewModel : ViewModel() {

    // Audio spectrum data
    private val _spectrumData = MutableStateFlow(FloatArray(512) { 0f })
    val spectrumData: StateFlow<FloatArray> = _spectrumData.asStateFlow()

    // Audio quality metrics
    data class AudioMetrics(
        val peakFrequency: Float = 0f,
        val lufs: Float = -23f,
        val dynamicRange: Float = 12f,
        val spectralCentroid: Float = 0f,
        val spectralRolloff: Float = 0f,
        val spectralFlatness: Float = 0f,
        val crestFactor: Float = 0f,
        val thd: Float = 0f,
        val snr: Float = 0f
    )

    private val _audioMetrics = MutableStateFlow(AudioMetrics())
    val audioMetrics: StateFlow<AudioMetrics> = _audioMetrics.asStateFlow()

    // Dynamic range processing metrics
    private val _gainReduction = MutableStateFlow(0f)
    val gainReduction: StateFlow<Float> = _gainReduction.asStateFlow()

    // Equalizer settings
    data class EqualizerSettings(
        val enabled: Boolean = false,
        val bandLevels: FloatArray = FloatArray(10) { 0f },
        val bassBoostStrength: Int = 0,
        val virtualizerStrength: Int = 0,
        val currentPreset: Int = 0
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false

            other as EqualizerSettings

            if (enabled != other.enabled) return false
            if (!bandLevels.contentEquals(other.bandLevels)) return false
            if (bassBoostStrength != other.bassBoostStrength) return false
            if (virtualizerStrength != other.virtualizerStrength) return false
            if (currentPreset != other.currentPreset) return false

            return true
        }

        override fun hashCode(): Int {
            var result = enabled.hashCode()
            result = 31 * result + bandLevels.contentHashCode()
            result = 31 * result + bassBoostStrength
            result = 31 * result + virtualizerStrength
            result = 31 * result + currentPreset
            return result
        }
    }

    private val _equalizerSettings = MutableStateFlow(EqualizerSettings())
    val equalizerSettings: StateFlow<EqualizerSettings> = _equalizerSettings.asStateFlow()

    // Professional audio processor settings
    data class ProcessorSettings(
        val enabled: Boolean = false,
        val compressionEnabled: Boolean = false,
        val compressionThreshold: Float = -12f,
        val compressionRatio: Float = 4f,
        val compressionAttack: Float = 5f,
        val compressionRelease: Float = 50f,
        val stereoWidth: Float = 1f,
        val autoGainEnabled: Boolean = false,
        val targetLufs: Float = -16f,
        val crossfeedEnabled: Boolean = false,
        val tubeWarmth: Float = 0f,
        val currentProfile: String = "None"
    )

    private val _processorSettings = MutableStateFlow(ProcessorSettings())
    val processorSettings: StateFlow<ProcessorSettings> = _processorSettings.asStateFlow()

    // State management for UI
    private val _isInitialized = MutableStateFlow(false)
    val isInitialized: StateFlow<Boolean> = _isInitialized.asStateFlow()

    /**
     * Update spectrum data from audio analysis
     */
    fun updateSpectrumData(magnitudes: FloatArray) {
        viewModelScope.launch {
            _spectrumData.value = magnitudes.copyOf()
            calculateAudioMetrics(magnitudes)
        }
    }

    /**
     * Calculate comprehensive audio quality metrics
     */
    private fun calculateAudioMetrics(magnitudes: FloatArray) {
        val sampleRate = 44100f
        val nyquist = sampleRate / 2f
        val freqStep = nyquist / magnitudes.size

        // Find peak frequency
        var peakIndex = 0
        var peakMagnitude = 0f
        for (i in magnitudes.indices) {
            if (magnitudes[i] > peakMagnitude) {
                peakMagnitude = magnitudes[i]
                peakIndex = i
            }
        }
        val peakFrequency = peakIndex * freqStep

        // Calculate spectral centroid (center of mass of spectrum)
        var weightedSum = 0f
        var magnitudeSum = 0f
        for (i in magnitudes.indices) {
            val frequency = i * freqStep
            weightedSum += frequency * magnitudes[i]
            magnitudeSum += magnitudes[i]
        }
        val spectralCentroid = if (magnitudeSum > 0) weightedSum / magnitudeSum else 0f

        // Calculate spectral rolloff (frequency below which 85% of energy is contained)
        val totalEnergy = magnitudes.map { it * it }.sum()
        val rolloffThreshold = totalEnergy * 0.85f
        var cumulativeEnergy = 0f
        var rolloffIndex = 0
        for (i in magnitudes.indices) {
            cumulativeEnergy += magnitudes[i] * magnitudes[i]
            if (cumulativeEnergy >= rolloffThreshold) {
                rolloffIndex = i
                break
            }
        }
        val spectralRolloff = rolloffIndex * freqStep

        // Calculate spectral flatness (measure of how noise-like vs tonal the spectrum is)
        val geometricMean = calculateGeometricMean(magnitudes)
        val arithmeticMean = magnitudes.average().toFloat()
        val spectralFlatness = if (arithmeticMean > 0) geometricMean / arithmeticMean else 0f

        // Calculate crest factor (peak to RMS ratio)
        val rms = sqrt(magnitudes.map { it * it }.average()).toFloat()
        val crestFactor = if (rms > 0) peakMagnitude / rms else 0f

        // Estimate LUFS (simplified calculation)
        val lufs = -23f + (20f * kotlin.math.log10(rms.coerceAtLeast(0.001f)))

        // Estimate dynamic range (simplified)
        val sortedMagnitudes = magnitudes.sorted()
        val p10 = sortedMagnitudes[(sortedMagnitudes.size * 0.1).toInt()]
        val p90 = sortedMagnitudes[(sortedMagnitudes.size * 0.9).toInt()]
        val dynamicRange = 20f * kotlin.math.log10(p90 / p10.coerceAtLeast(0.001f))

        // Estimate THD (Total Harmonic Distortion) - simplified
        val fundamentalIndex = magnitudes.indexOfFirst { it == peakMagnitude }
        var harmonicPower = 0f
        var harmonicCount = 0
        for (harmonic in 2..5) {
            val harmonicIndex = fundamentalIndex * harmonic
            if (harmonicIndex < magnitudes.size) {
                harmonicPower += magnitudes[harmonicIndex] * magnitudes[harmonicIndex]
                harmonicCount++
            }
        }
        val fundamentalPower = peakMagnitude * peakMagnitude
        val thd = if (fundamentalPower > 0 && harmonicCount > 0) {
            100f * sqrt(harmonicPower) / sqrt(fundamentalPower)
        } else 0f

        // Estimate SNR (Signal to Noise Ratio)
        val signalPower = magnitudes.take(magnitudes.size / 2).map { it * it }.average().toFloat()
        val noisePower = magnitudes.takeLast(magnitudes.size / 4).map { it * it }.average().toFloat()
        val snr = if (noisePower > 0) 10f * kotlin.math.log10(signalPower / noisePower) else 0f

        _audioMetrics.value = AudioMetrics(
            peakFrequency = peakFrequency,
            lufs = lufs.coerceIn(-60f, 0f),
            dynamicRange = dynamicRange.coerceIn(0f, 40f),
            spectralCentroid = spectralCentroid,
            spectralRolloff = spectralRolloff,
            spectralFlatness = spectralFlatness.coerceIn(0f, 1f),
            crestFactor = crestFactor.coerceIn(1f, 20f),
            thd = thd.coerceIn(0f, 10f),
            snr = snr.coerceIn(0f, 80f)
        )
    }

    /**
     * Calculate geometric mean of array values
     */
    private fun calculateGeometricMean(values: FloatArray): Float {
        if (values.isEmpty()) return 0f
        
        var logSum = 0f
        var validCount = 0
        
        for (value in values) {
            if (value > 0) {
                logSum += kotlin.math.ln(value)
                validCount++
            }
        }
        
        return if (validCount > 0) {
            kotlin.math.exp(logSum / validCount).toFloat()
        } else 0f
    }

    /**
     * Update gain reduction meter from compressor
     */
    fun updateGainReduction(reduction: Float) {
        viewModelScope.launch {
            _gainReduction.value = abs(reduction).coerceIn(0f, 20f)
        }
    }

    /**
     * Update equalizer settings
     */
    fun updateEqualizerSettings(settings: EqualizerSettings) {
        viewModelScope.launch {
            _equalizerSettings.value = settings
        }
    }

    /**
     * Update processor settings
     */
    fun updateProcessorSettings(settings: ProcessorSettings) {
        viewModelScope.launch {
            _processorSettings.value = settings
        }
    }

    /**
     * Set band level for specific frequency band
     */
    fun setBandLevel(bandIndex: Int, level: Float) {
        viewModelScope.launch {
            val currentSettings = _equalizerSettings.value
            val newBandLevels = currentSettings.bandLevels.copyOf()
            if (bandIndex in newBandLevels.indices) {
                newBandLevels[bandIndex] = level
                _equalizerSettings.value = currentSettings.copy(bandLevels = newBandLevels)
            }
        }
    }

    /**
     * Update compression settings
     */
    fun updateCompressionSettings(
        threshold: Float,
        ratio: Float,
        attack: Float,
        release: Float
    ) {
        viewModelScope.launch {
            val currentSettings = _processorSettings.value
            _processorSettings.value = currentSettings.copy(
                compressionThreshold = threshold,
                compressionRatio = ratio,
                compressionAttack = attack,
                compressionRelease = release
            )
        }
    }

    /**
     * Toggle professional processor
     */
    fun toggleProfessionalProcessor(enabled: Boolean) {
        viewModelScope.launch {
            val currentSettings = _processorSettings.value
            _processorSettings.value = currentSettings.copy(enabled = enabled)
        }
    }

    /**
     * Load audio profile
     */
    fun loadAudioProfile(profileName: String) {
        viewModelScope.launch {
            val currentSettings = _processorSettings.value
            _processorSettings.value = currentSettings.copy(currentProfile = profileName)
        }
    }

    /**
     * Reset all settings to defaults
     */
    fun resetToDefaults() {
        viewModelScope.launch {
            _equalizerSettings.value = EqualizerSettings()
            _processorSettings.value = ProcessorSettings()
            _audioMetrics.value = AudioMetrics()
            _gainReduction.value = 0f
        }
    }

    /**
     * Mark initialization as complete
     */
    fun setInitialized(initialized: Boolean) {
        viewModelScope.launch {
            _isInitialized.value = initialized
        }
    }

    override fun onCleared() {
        super.onCleared()
        // Clean up any resources if needed
    }
}