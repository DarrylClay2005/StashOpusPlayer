package com.stash.opusplayer.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.Visualizer
import android.util.Log
import androidx.preference.PreferenceManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.*

/**
 * Audio Analysis Engine
 * 
 * Provides real-time audio analysis including:
 * - Spectrum visualization
 * - Peak level detection  
 * - Dynamic range monitoring
 * - Frequency content analysis
 * - Audio quality metrics
 * - Loudness analysis (LUFS)
 * - Phase correlation analysis
 * - Harmonic distortion detection
 */
class AudioAnalysisEngine(private val context: Context) {
    
    companion object {
        private const val TAG = "AudioAnalysisEngine"
        
        // Preference keys
        private const val PREF_ANALYSIS_ENABLED = "analysis_enabled"
        private const val PREF_VISUALIZATION_ENABLED = "visualization_enabled"
        private const val PREF_PEAK_DETECTION = "peak_detection_enabled"
        private const val PREF_SPECTRUM_RESOLUTION = "spectrum_resolution"
        private const val PREF_ANALYSIS_RATE = "analysis_rate"
        private const val PREF_SMOOTHING_FACTOR = "smoothing_factor"
        
        // Analysis parameters
        private const val DEFAULT_CAPTURE_SIZE = 1024
        private const val SAMPLE_RATE = 44100f
        private const val MIN_FREQUENCY = 20.0f
        private const val MAX_FREQUENCY = 20000.0f
        private const val LUFS_GATE_THRESHOLD = -70.0f
        private const val LUFS_RELATIVE_GATE_OFFSET = -10.0f
        
        // Spectrum bins
        private const val SPECTRUM_BINS = 64
        private const val PEAK_HISTORY_SIZE = 100
        
        // Quality thresholds
        private const val HIGH_QUALITY_DR_THRESHOLD = 14.0f
        private const val GOOD_QUALITY_DR_THRESHOLD = 8.0f
        private const val DISTORTION_THRESHOLD = 0.03f
        private const val PEAK_THRESHOLD_DB = -3.0f
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    // Android Audio Effects
    private var visualizer: Visualizer? = null
    
    // Analysis data storage
    private val spectrumHistory = Array(10) { FloatArray(SPECTRUM_BINS) }
    private var historyIndex = 0
    private val peakHistory = mutableListOf<Float>()
    private var lufsIntegrationBuffer = mutableListOf<Float>()
    
    // State flows for UI
    private val _analysisEnabled = MutableStateFlow(false)
    val analysisEnabled: StateFlow<Boolean> = _analysisEnabled.asStateFlow()
    
    private val _visualizationEnabled = MutableStateFlow(true)
    val visualizationEnabled: StateFlow<Boolean> = _visualizationEnabled.asStateFlow()
    
    private val _peakDetectionEnabled = MutableStateFlow(true)
    val peakDetectionEnabled: StateFlow<Boolean> = _peakDetectionEnabled.asStateFlow()
    
    private val _spectrumResolution = MutableStateFlow(SPECTRUM_BINS)
    val spectrumResolution: StateFlow<Int> = _spectrumResolution.asStateFlow()
    
    private val _analysisRate = MutableStateFlow(20) // Hz
    val analysisRate: StateFlow<Int> = _analysisRate.asStateFlow()
    
    private val _smoothingFactor = MutableStateFlow(0.8f)
    val smoothingFactor: StateFlow<Float> = _smoothingFactor.asStateFlow()
    
    // Real-time analysis data
    private val _spectrumData = MutableStateFlow(FloatArray(SPECTRUM_BINS) { 0.0f })
    val spectrumData: StateFlow<FloatArray> = _spectrumData.asStateFlow()
    
    private val _waveformData = MutableStateFlow(ByteArray(DEFAULT_CAPTURE_SIZE) { 0 })
    val waveformData: StateFlow<ByteArray> = _waveformData.asStateFlow()
    
    private val _currentPeakDb = MutableStateFlow(-60.0f)
    val currentPeakDb: StateFlow<Float> = _currentPeakDb.asStateFlow()
    
    private val _currentRmsDb = MutableStateFlow(-60.0f)
    val currentRmsDb: StateFlow<Float> = _currentRmsDb.asStateFlow()
    
    private val _currentLufs = MutableStateFlow(-23.0f)
    val currentLufs: StateFlow<Float> = _currentLufs.asStateFlow()
    
    private val _dynamicRange = MutableStateFlow(12.0f)
    val dynamicRange: StateFlow<Float> = _dynamicRange.asStateFlow()
    
    private val _stereoCorrelation = MutableStateFlow(0.0f)
    val stereoCorrelation: StateFlow<Float> = _stereoCorrelation.asStateFlow()
    
    private val _thd = MutableStateFlow(0.0f)
    val thd: StateFlow<Float> = _thd.asStateFlow()
    
    private val _spectralCentroid = MutableStateFlow(2000.0f)
    val spectralCentroid: StateFlow<Float> = _spectralCentroid.asStateFlow()
    
    private val _spectralFlatness = MutableStateFlow(0.5f)
    val spectralFlatness: StateFlow<Float> = _spectralFlatness.asStateFlow()
    
    // Audio quality metrics
    private val _audioQuality = MutableStateFlow(AudioQuality())
    val audioQuality: StateFlow<AudioQuality> = _audioQuality.asStateFlow()
    
    // Peak detection
    private val _peaksDetected = MutableStateFlow(listOf<Peak>())
    val peaksDetected: StateFlow<List<Peak>> = _peaksDetected.asStateFlow()
    
    // Frequency analysis
    private val _dominantFrequencies = MutableStateFlow(listOf<FrequencyPeak>())
    val dominantFrequencies: StateFlow<List<FrequencyPeak>> = _dominantFrequencies.asStateFlow()
    
    fun initialize(audioSessionId: Int) {
        try {
            release()
            
            // Initialize Visualizer
            try {
                visualizer = Visualizer(audioSessionId).apply {
                    captureSize = DEFAULT_CAPTURE_SIZE
                    enabled = false
                }
                
                // Set up data capture listener
                visualizer?.setDataCaptureListener(
                    object : Visualizer.OnDataCaptureListener {
                        override fun onWaveFormDataCapture(
                            visualizer: Visualizer?,
                            waveform: ByteArray?,
                            samplingRate: Int
                        ) {
                            waveform?.let { 
                                _waveformData.value = it
                                if (_analysisEnabled.value) {
                                    analyzeWaveform(it)
                                }
                            }
                        }
                        
                        override fun onFftDataCapture(
                            visualizer: Visualizer?,
                            fft: ByteArray?,
                            samplingRate: Int
                        ) {
                            fft?.let { 
                                if (_analysisEnabled.value) {
                                    analyzeFftData(it)
                                }
                            }
                        }
                    },
                    Visualizer.getMaxCaptureRate(),
                    true,
                    true
                )
                
            } catch (e: Exception) {
                Log.w(TAG, "Visualizer not supported", e)
            }
            
            loadSettings()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing audio analysis engine", e)
        }
    }
    
    fun release() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
            visualizer = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing audio analysis engine", e)
        }
    }
    
    // Main control functions
    fun setAnalysisEnabled(enabled: Boolean) {
        _analysisEnabled.value = enabled
        prefs.edit().putBoolean(PREF_ANALYSIS_ENABLED, enabled).apply()
        
        visualizer?.enabled = enabled && _visualizationEnabled.value
        
        if (!enabled) {
            // Reset analysis data
            resetAnalysisData()
        }
    }
    
    fun setVisualizationEnabled(enabled: Boolean) {
        _visualizationEnabled.value = enabled
        prefs.edit().putBoolean(PREF_VISUALIZATION_ENABLED, enabled).apply()
        
        visualizer?.enabled = enabled && _analysisEnabled.value
    }
    
    fun setPeakDetectionEnabled(enabled: Boolean) {
        _peakDetectionEnabled.value = enabled
        prefs.edit().putBoolean(PREF_PEAK_DETECTION, enabled).apply()
    }
    
    fun setSpectrumResolution(resolution: Int) {
        val validResolution = resolution.coerceIn(32, 128)
        _spectrumResolution.value = validResolution
        prefs.edit().putInt(PREF_SPECTRUM_RESOLUTION, validResolution).apply()
        
        // Reinitialize spectrum data array
        _spectrumData.value = FloatArray(validResolution) { 0.0f }
    }
    
    fun setAnalysisRate(rate: Int) {
        val validRate = rate.coerceIn(5, 60)
        _analysisRate.value = validRate
        prefs.edit().putInt(PREF_ANALYSIS_RATE, validRate).apply()
        
        // Update visualizer rate if supported
        try {
            // Note: Can't update existing listener rate dynamically
            // Would need to recreate the visualizer with new settings
        } catch (e: Exception) {
            Log.w(TAG, "Could not update analysis rate", e)
        }
    }
    
    fun setSmoothingFactor(factor: Float) {
        _smoothingFactor.value = factor.coerceIn(0.1f, 0.95f)
        prefs.edit().putFloat(PREF_SMOOTHING_FACTOR, _smoothingFactor.value).apply()
    }

    fun analyzeSamples(samples: FloatArray) {
        if (!_analysisEnabled.value || samples.isEmpty()) return

        try {
            val normalizedSamples = samples.map { it.coerceIn(-1f, 1f) }.toFloatArray()
            val rms = sqrt(normalizedSamples.map { it * it }.average()).toFloat()
            val peak = normalizedSamples.maxOf { abs(it) }
            val rmsDb = if (rms > 0) 20 * log10(rms) else -60.0f
            val peakDb = if (peak > 0) 20 * log10(peak) else -60.0f
            val smoothing = _smoothingFactor.value

            _currentRmsDb.value = _currentRmsDb.value * smoothing + rmsDb * (1 - smoothing)
            _currentPeakDb.value = _currentPeakDb.value * smoothing + peakDb * (1 - smoothing)

            peakHistory.add(peakDb)
            if (peakHistory.size > PEAK_HISTORY_SIZE) {
                peakHistory.removeAt(0)
            }
            if (peakHistory.size >= 10) {
                val sortedPeaks = peakHistory.sorted()
                val p95 = sortedPeaks[(sortedPeaks.size * 0.95).toInt()]
                val p5 = sortedPeaks[(sortedPeaks.size * 0.05).toInt()]
                _dynamicRange.value = p95 - p5
            }

            lufsIntegrationBuffer.add(rms)
            if (lufsIntegrationBuffer.size > SAMPLE_RATE.toInt() * 3) {
                lufsIntegrationBuffer.removeAt(0)
            }
            if (lufsIntegrationBuffer.size >= SAMPLE_RATE.toInt()) {
                _currentLufs.value = calculateLufs(lufsIntegrationBuffer)
            }

            if (_peakDetectionEnabled.value && peakDb > PEAK_THRESHOLD_DB) {
                detectPeaks(normalizedSamples)
            }
            _thd.value = calculateTHD(normalizedSamples)

            val spectrum = FloatArray(_spectrumResolution.value) { bin ->
                val binFrequency = binToFrequency(bin, _spectrumResolution.value)
                val amplitude = getFrequencyAmplitude(normalizedSamples, binFrequency).coerceAtLeast(1e-6f)
                (20 * log10(amplitude)).coerceIn(-80.0f, 0.0f)
            }

            val smoothed = _spectrumData.value.clone()
            for (i in spectrum.indices) {
                if (i < smoothed.size) {
                    smoothed[i] = smoothed[i] * smoothing + spectrum[i] * (1 - smoothing)
                }
            }

            _spectrumData.value = smoothed
            spectrumHistory[historyIndex] = smoothed.clone()
            historyIndex = (historyIndex + 1) % spectrumHistory.size
            _spectralCentroid.value = calculateSpectralCentroid(smoothed)
            _spectralFlatness.value = calculateSpectralFlatness(smoothed)
            _dominantFrequencies.value = findDominantFrequencies(smoothed)
            updateAudioQuality()
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing raw audio samples", e)
        }
    }
    
    private fun analyzeWaveform(waveform: ByteArray) {
        try {
            // Convert to float samples
            val samples = waveform.map { (it.toInt() - 128) / 128.0f }.toFloatArray()
            
            // Calculate RMS and peak levels
            val rms = sqrt(samples.map { it * it }.average()).toFloat()
            val peak = samples.maxOf { abs(it) }
            
            val rmsDb = if (rms > 0) 20 * log10(rms) else -60.0f
            val peakDb = if (peak > 0) 20 * log10(peak) else -60.0f
            
            // Apply smoothing
            val smoothing = _smoothingFactor.value
            _currentRmsDb.value = _currentRmsDb.value * smoothing + rmsDb * (1 - smoothing)
            _currentPeakDb.value = _currentPeakDb.value * smoothing + peakDb * (1 - smoothing)
            
            // Update peak history
            peakHistory.add(peakDb)
            if (peakHistory.size > PEAK_HISTORY_SIZE) {
                peakHistory.removeAt(0)
            }
            
            // Calculate dynamic range from peak history
            if (peakHistory.size >= 10) {
                val sortedPeaks = peakHistory.sorted()
                val p95 = sortedPeaks[(sortedPeaks.size * 0.95).toInt()]
                val p5 = sortedPeaks[(sortedPeaks.size * 0.05).toInt()]
                _dynamicRange.value = p95 - p5
            }
            
            // Update LUFS integration buffer
            lufsIntegrationBuffer.add(rms)
            if (lufsIntegrationBuffer.size > SAMPLE_RATE.toInt() * 3) { // 3 second integration
                lufsIntegrationBuffer.removeAt(0)
            }
            
            // Calculate integrated LUFS
            if (lufsIntegrationBuffer.size >= SAMPLE_RATE.toInt()) {
                _currentLufs.value = calculateLufs(lufsIntegrationBuffer)
            }
            
            // Detect peaks if enabled
            if (_peakDetectionEnabled.value && peakDb > PEAK_THRESHOLD_DB) {
                detectPeaks(samples)
            }
            
            // Calculate THD (simplified)
            _thd.value = calculateTHD(samples)
            
            // Update audio quality metrics
            updateAudioQuality()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing waveform", e)
        }
    }
    
    private fun analyzeFftData(fft: ByteArray) {
        try {
            // Convert FFT data to magnitude spectrum
            val spectrum = convertFftToSpectrum(fft)
            
            // Smooth spectrum data
            val currentSpectrum = _spectrumData.value
            val smoothing = _smoothingFactor.value
            
            for (i in spectrum.indices) {
                if (i < currentSpectrum.size) {
                    currentSpectrum[i] = currentSpectrum[i] * smoothing + spectrum[i] * (1 - smoothing)
                }
            }
            
            _spectrumData.value = currentSpectrum.clone()
            
            // Update spectrum history
            spectrumHistory[historyIndex] = currentSpectrum.clone()
            historyIndex = (historyIndex + 1) % spectrumHistory.size
            
            // Calculate spectral features
            _spectralCentroid.value = calculateSpectralCentroid(currentSpectrum)
            _spectralFlatness.value = calculateSpectralFlatness(currentSpectrum)
            
            // Find dominant frequencies
            _dominantFrequencies.value = findDominantFrequencies(currentSpectrum)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing FFT data", e)
        }
    }
    
    private fun convertFftToSpectrum(fft: ByteArray): FloatArray {
        val spectrumSize = min(_spectrumResolution.value, fft.size / 2)
        val spectrum = FloatArray(spectrumSize)
        
        for (i in 0 until spectrumSize) {
            val real = fft[i * 2].toFloat()
            val imag = fft[i * 2 + 1].toFloat()
            val magnitude = sqrt(real * real + imag * imag)
            
            // Convert to dB with noise floor
            spectrum[i] = if (magnitude > 0) {
                (20 * log10(magnitude + 1e-6f)).coerceIn(-80.0f, 0.0f)
            } else {
                -80.0f
            }
        }
        
        return spectrum
    }
    
    private fun calculateSpectralCentroid(spectrum: FloatArray): Float {
        var weightedSum = 0.0f
        var magnitudeSum = 0.0f
        
        for (i in spectrum.indices) {
            val frequency = binToFrequency(i, spectrum.size)
            val magnitude = dbToLinear(spectrum[i])
            
            weightedSum += frequency * magnitude
            magnitudeSum += magnitude
        }
        
        return if (magnitudeSum > 0) weightedSum / magnitudeSum else 2000.0f
    }
    
    private fun calculateSpectralFlatness(spectrum: FloatArray): Float {
        var geometricMean = 0.0f
        var arithmeticMean = 0.0f
        var count = 0
        
        for (magnitude in spectrum) {
            val linear = dbToLinear(magnitude)
            if (linear > 1e-10f) {
                geometricMean += ln(linear)
                arithmeticMean += linear
                count++
            }
        }
        
        return if (count > 0) {
            val gm = kotlin.math.exp(geometricMean / count)
            val am = arithmeticMean / count
            if (am > 0) gm / am else 0.0f
        } else 0.0f
    }
    
    private fun findDominantFrequencies(spectrum: FloatArray): List<FrequencyPeak> {
        val peaks = mutableListOf<FrequencyPeak>()
        val threshold = spectrum.maxOrNull()?.minus(20) ?: -60.0f // 20dB below peak
        
        for (i in 1 until spectrum.size - 1) {
            if (spectrum[i] > spectrum[i - 1] && 
                spectrum[i] > spectrum[i + 1] && 
                spectrum[i] > threshold) {
                
                val frequency = binToFrequency(i, spectrum.size)
                val magnitude = spectrum[i]
                peaks.add(FrequencyPeak(frequency, magnitude))
            }
        }
        
        // Sort by magnitude and return top 10
        return peaks.sortedByDescending { it.magnitude }.take(10)
    }
    
    private fun binToFrequency(bin: Int, spectrumSize: Int): Float {
        return bin * SAMPLE_RATE / (2 * spectrumSize)
    }
    
    private fun dbToLinear(db: Float): Float {
        return 10.0f.pow(db / 20.0f)
    }
    
    private fun calculateLufs(samples: List<Float>): Float {
        if (samples.isEmpty()) return -23.0f
        
        // Apply K-weighting filter (simplified)
        val kWeighted = applyKWeighting(samples)
        
        // Calculate mean square with gating
        val meanSquare = kWeighted.filter { it > LUFS_GATE_THRESHOLD }
            .map { it * it }
            .average()
        
        // Convert to LUFS
        return if (meanSquare > 0) {
            -0.691f + 10 * log10(meanSquare.toFloat())
        } else {
            -70.0f
        }
    }
    
    private fun applyKWeighting(samples: List<Float>): List<Float> {
        // Simplified K-weighting filter
        // In a real implementation, this would be a proper biquad filter cascade
        return samples.map { sample ->
            // High-shelf filter approximation at 1.5kHz
            val highShelf = sample * 1.5f
            // High-pass filter approximation at 38Hz  
            val highPass = sample * 0.98f
            (highShelf + highPass) * 0.5f
        }
    }
    
    private fun detectPeaks(samples: FloatArray) {
        val peaks = mutableListOf<Peak>()
        val windowSize = samples.size / 10 // 10 analysis windows
        
        for (window in 0 until 10) {
            val startIdx = window * windowSize
            val endIdx = min(startIdx + windowSize, samples.size)
            
            if (endIdx > startIdx) {
                val windowSamples = samples.sliceArray(startIdx until endIdx)
                val peak = windowSamples.maxOf { abs(it) }
                val peakDb = if (peak > 0) 20 * log10(peak) else -60.0f
                
                if (peakDb > PEAK_THRESHOLD_DB) {
                    val timeMs = (startIdx.toFloat() / SAMPLE_RATE * 1000).toInt()
                    peaks.add(Peak(timeMs, peakDb))
                }
            }
        }
        
        _peaksDetected.value = peaks.take(20) // Limit to recent peaks
    }
    
    private fun calculateTHD(samples: FloatArray): Float {
        // Simplified THD calculation
        // In a real implementation, this would use proper harmonic analysis
        try {
            val fundamental = findFundamentalFrequency(samples)
            if (fundamental < 20.0f) return 0.0f
            
            val harmonicEnergy = calculateHarmonicEnergy(samples, fundamental)
            val totalEnergy = samples.map { it * it }.sum()
            
            return if (totalEnergy > 0) {
                sqrt(harmonicEnergy / totalEnergy).coerceAtMost(1.0f)
            } else 0.0f
            
        } catch (e: Exception) {
            return 0.0f
        }
    }
    
    private fun findFundamentalFrequency(samples: FloatArray): Float {
        // Autocorrelation-based pitch detection (simplified)
        var bestPeriod = 0
        var maxCorrelation = 0.0f
        
        val minPeriod = (SAMPLE_RATE / MAX_FREQUENCY).toInt()
        val maxPeriod = (SAMPLE_RATE / MIN_FREQUENCY).toInt().coerceAtMost(samples.size / 2)
        
        for (period in minPeriod..maxPeriod) {
            var correlation = 0.0f
            var count = 0
            
            for (i in 0 until samples.size - period) {
                correlation += samples[i] * samples[i + period]
                count++
            }
            
            correlation /= count
            
            if (correlation > maxCorrelation) {
                maxCorrelation = correlation
                bestPeriod = period
            }
        }
        
        return if (bestPeriod > 0) SAMPLE_RATE / bestPeriod else 0.0f
    }
    
    private fun calculateHarmonicEnergy(samples: FloatArray, fundamental: Float): Float {
        // Simplified harmonic energy calculation
        var harmonicEnergy = 0.0f
        
        for (harmonic in 2..5) { // Check up to 5th harmonic
            val harmonicFreq = fundamental * harmonic
            if (harmonicFreq < MAX_FREQUENCY) {
                val harmonicAmplitude = getFrequencyAmplitude(samples, harmonicFreq)
                harmonicEnergy += harmonicAmplitude * harmonicAmplitude
            }
        }
        
        return harmonicEnergy
    }
    
    private fun getFrequencyAmplitude(samples: FloatArray, frequency: Float): Float {
        // Simplified frequency amplitude estimation using DFT
        var real = 0.0f
        var imag = 0.0f
        
        val normalizedFreq = frequency / SAMPLE_RATE
        
        for (i in samples.indices) {
            val angle = 2 * PI * normalizedFreq * i
            real += samples[i] * cos(angle).toFloat()
            imag += samples[i] * sin(angle).toFloat()
        }
        
        return sqrt(real * real + imag * imag) / samples.size
    }
    
    private fun updateAudioQuality() {
        val dr = _dynamicRange.value
        val thd = _thd.value
        val peak = _currentPeakDb.value
        
        val quality = AudioQuality(
            dynamicRange = dr,
            totalHarmonicDistortion = thd,
            peakLevel = peak,
            qualityRating = calculateQualityRating(dr, thd, peak),
            hasClipping = peak > -0.1f,
            hasDistortion = thd > DISTORTION_THRESHOLD,
            isCompressed = dr < GOOD_QUALITY_DR_THRESHOLD,
            spectralBalance = calculateSpectralBalanceRating()
        )
        
        _audioQuality.value = quality
    }
    
    private fun calculateQualityRating(dr: Float, thd: Float, peak: Float): AudioQualityRating {
        var score = 100
        
        // Dynamic range scoring
        score -= when {
            dr < 6.0f -> 40
            dr < 8.0f -> 25
            dr < 12.0f -> 10
            else -> 0
        }
        
        // THD scoring
        score -= when {
            thd > 0.05f -> 30
            thd > 0.03f -> 15
            thd > 0.01f -> 5
            else -> 0
        }
        
        // Peak level scoring
        if (peak > -0.1f) score -= 20
        else if (peak > -1.0f) score -= 10
        
        return when {
            score >= 85 -> AudioQualityRating.EXCELLENT
            score >= 70 -> AudioQualityRating.GOOD
            score >= 50 -> AudioQualityRating.FAIR
            else -> AudioQualityRating.POOR
        }
    }
    
    private fun calculateSpectralBalanceRating(): SpectralBalanceRating {
        val spectrum = _spectrumData.value
        if (spectrum.isEmpty()) return SpectralBalanceRating.BALANCED
        
        val bassEnergy = spectrum.take(spectrum.size / 4).average()
        val midEnergy = spectrum.drop(spectrum.size / 4).take(spectrum.size / 2).average()
        val trebleEnergy = spectrum.takeLast(spectrum.size / 4).average()
        
        val totalEnergy = (bassEnergy + midEnergy + trebleEnergy) / 3
        
        return when {
            abs(bassEnergy - totalEnergy) > 6.0f -> SpectralBalanceRating.BASS_HEAVY
            abs(trebleEnergy - totalEnergy) > 6.0f -> SpectralBalanceRating.TREBLE_HEAVY
            abs(midEnergy - totalEnergy) > 6.0f -> SpectralBalanceRating.MID_HEAVY
            else -> SpectralBalanceRating.BALANCED
        }
    }
    
    // Stereo analysis (requires stereo input)
    fun analyzeStereoContent(leftChannel: FloatArray, rightChannel: FloatArray) {
        try {
            if (leftChannel.size != rightChannel.size) return
            
            // Calculate cross-correlation
            var correlation = 0.0f
            var leftEnergy = 0.0f
            var rightEnergy = 0.0f
            
            for (i in leftChannel.indices) {
                correlation += leftChannel[i] * rightChannel[i]
                leftEnergy += leftChannel[i] * leftChannel[i]
                rightEnergy += rightChannel[i] * rightChannel[i]
            }
            
            val normalization = sqrt(leftEnergy * rightEnergy)
            _stereoCorrelation.value = if (normalization > 0) {
                correlation / normalization
            } else 0.0f
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing stereo content", e)
        }
    }
    
    private fun resetAnalysisData() {
        _spectrumData.value = FloatArray(_spectrumResolution.value) { 0.0f }
        _currentPeakDb.value = -60.0f
        _currentRmsDb.value = -60.0f
        _currentLufs.value = -23.0f
        _dynamicRange.value = 12.0f
        _thd.value = 0.0f
        _peaksDetected.value = emptyList()
        _dominantFrequencies.value = emptyList()
        peakHistory.clear()
        lufsIntegrationBuffer.clear()
    }
    
    private fun loadSettings() {
        _analysisEnabled.value = prefs.getBoolean(PREF_ANALYSIS_ENABLED, false)
        _visualizationEnabled.value = prefs.getBoolean(PREF_VISUALIZATION_ENABLED, true)
        _peakDetectionEnabled.value = prefs.getBoolean(PREF_PEAK_DETECTION, true)
        _spectrumResolution.value = prefs.getInt(PREF_SPECTRUM_RESOLUTION, SPECTRUM_BINS)
        _analysisRate.value = prefs.getInt(PREF_ANALYSIS_RATE, 20)
        _smoothingFactor.value = prefs.getFloat(PREF_SMOOTHING_FACTOR, 0.8f)
        
        // Initialize with loaded settings
        setSpectrumResolution(_spectrumResolution.value)
        setAnalysisRate(_analysisRate.value)
    }
    
    // Utility functions for external access
    fun getFrequencyForBin(bin: Int): Float {
        return binToFrequency(bin, _spectrumResolution.value)
    }
    
    fun getBinForFrequency(frequency: Float): Int {
        val bin = (frequency * _spectrumResolution.value * 2 / SAMPLE_RATE).toInt()
        return bin.coerceIn(0, _spectrumResolution.value - 1)
    }
}

enum class AudioQualityRating {
    EXCELLENT,
    GOOD,
    FAIR,
    POOR
}

enum class SpectralBalanceRating {
    BALANCED,
    BASS_HEAVY,
    MID_HEAVY,
    TREBLE_HEAVY
}

data class AudioQuality(
    val dynamicRange: Float = 12.0f,
    val totalHarmonicDistortion: Float = 0.0f,
    val peakLevel: Float = -12.0f,
    val qualityRating: AudioQualityRating = AudioQualityRating.GOOD,
    val hasClipping: Boolean = false,
    val hasDistortion: Boolean = false,
    val isCompressed: Boolean = false,
    val spectralBalance: SpectralBalanceRating = SpectralBalanceRating.BALANCED
)

data class Peak(
    val timeMs: Int,
    val levelDb: Float
)

data class FrequencyPeak(
    val frequency: Float,
    val magnitude: Float
)
