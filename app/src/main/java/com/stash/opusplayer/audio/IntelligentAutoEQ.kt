package com.stash.opusplayer.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.Equalizer
import android.util.Log
import androidx.preference.PreferenceManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.*

/**
 * Intelligent Auto-EQ System
 * 
 * Provides smart equalizer functionality including:
 * - Automatic genre-based EQ optimization
 * - Real-time audio content analysis
 * - Dynamic EQ adjustment based on song characteristics
 * - Learning from user preferences
 * - Smart frequency balancing
 * - Loudness compensation
 */
class IntelligentAutoEQ(private val context: Context) {
    
    companion object {
        private const val TAG = "IntelligentAutoEQ"
        
        // Preference keys
        private const val PREF_AUTO_EQ_ENABLED = "auto_eq_enabled"
        private const val PREF_GENRE_OPTIMIZATION = "genre_optimization_enabled"
        private const val PREF_DYNAMIC_ADJUSTMENT = "dynamic_adjustment_enabled"
        private const val PREF_LEARNING_ENABLED = "learning_enabled"
        private const val PREF_LOUDNESS_COMPENSATION = "loudness_compensation"
        private const val PREF_REFERENCE_CURVE = "reference_curve"
        private const val PREF_ADAPTATION_SPEED = "adaptation_speed"
        private const val PREF_FREQUENCY_SENSITIVITY = "frequency_sensitivity"
        
        // Analysis parameters
        private const val FFT_SIZE = 2048
        private const val SAMPLE_RATE = 44100f
        private const val ANALYSIS_WINDOW_MS = 100
        private const val ADAPTATION_SMOOTHING = 0.95f
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    // Android Audio Effects
    private var equalizer: Equalizer? = null
    
    // Analysis data
    private var frequencyAnalysis = FloatArray(FFT_SIZE / 2) { 0.0f }
    private var spectralCentroid = 0.0f
    private var spectralSpread = 0.0f
    private var spectralRolloff = 0.0f
    private var zeroCrossingRate = 0.0f
    private var mfcc = FloatArray(13) { 0.0f }
    
    // Learning data
    private val genreProfiles = mutableMapOf<String, EQProfile>()
    private val userAdjustments = mutableListOf<UserAdjustment>()
    
    // State flows for UI
    private val _autoEQEnabled = MutableStateFlow(false)
    val autoEQEnabled: StateFlow<Boolean> = _autoEQEnabled.asStateFlow()
    
    private val _genreOptimization = MutableStateFlow(true)
    val genreOptimization: StateFlow<Boolean> = _genreOptimization.asStateFlow()
    
    private val _dynamicAdjustment = MutableStateFlow(true)
    val dynamicAdjustment: StateFlow<Boolean> = _dynamicAdjustment.asStateFlow()
    
    private val _learningEnabled = MutableStateFlow(true)
    val learningEnabled: StateFlow<Boolean> = _learningEnabled.asStateFlow()
    
    private val _loudnessCompensation = MutableStateFlow(0.5f)
    val loudnessCompensation: StateFlow<Float> = _loudnessCompensation.asStateFlow()
    
    private val _referenceCurve = MutableStateFlow(ReferenceCurve.FLAT)
    val referenceCurve: StateFlow<ReferenceCurve> = _referenceCurve.asStateFlow()
    
    private val _adaptationSpeed = MutableStateFlow(0.5f)
    val adaptationSpeed: StateFlow<Float> = _adaptationSpeed.asStateFlow()
    
    private val _frequencySensitivity = MutableStateFlow(0.7f)
    val frequencySensitivity: StateFlow<Float> = _frequencySensitivity.asStateFlow()
    
    // Current analysis state
    private val _currentGenre = MutableStateFlow("Unknown")
    val currentGenre: StateFlow<String> = _currentGenre.asStateFlow()
    
    private val _detectedTempo = MutableStateFlow(120.0f)
    val detectedTempo: StateFlow<Float> = _detectedTempo.asStateFlow()
    
    private val _spectralBalance = MutableStateFlow(SpectralBalance())
    val spectralBalance: StateFlow<SpectralBalance> = _spectralBalance.asStateFlow()
    
    private val _eqAdjustments = MutableStateFlow(FloatArray(0))
    val eqAdjustments: StateFlow<FloatArray> = _eqAdjustments.asStateFlow()
    
    fun initialize(audioSessionId: Int) {
        try {
            release()
            
            // Initialize Equalizer
            try {
                equalizer = Equalizer(0, audioSessionId).apply {
                    enabled = false
                }
                
                // Initialize EQ adjustments array
                equalizer?.let { eq ->
                    val numBands = eq.numberOfBands.toInt()
                    _eqAdjustments.value = FloatArray(numBands) { 0.0f }
                }
                
            } catch (e: Exception) {
                Log.w(TAG, "Equalizer not supported", e)
            }
            
            initializeGenreProfiles()
            loadSettings()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing intelligent auto-EQ", e)
        }
    }
    
    fun release() {
        try {
            equalizer?.release()
            equalizer = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing intelligent auto-EQ", e)
        }
    }
    
    // Main auto-EQ control
    fun setAutoEQEnabled(enabled: Boolean) {
        _autoEQEnabled.value = enabled
        prefs.edit().putBoolean(PREF_AUTO_EQ_ENABLED, enabled).apply()
        
        equalizer?.let { eq ->
            if (enabled) {
                applyCurrentEQSettings()
            } else {
                // Reset to flat response
                for (band in 0 until eq.numberOfBands) {
                    eq.setBandLevel(band.toShort(), 0.toShort())
                }
            }
            eq.enabled = enabled
        }
    }
    
    fun setGenreOptimizationEnabled(enabled: Boolean) {
        _genreOptimization.value = enabled
        prefs.edit().putBoolean(PREF_GENRE_OPTIMIZATION, enabled).apply()
        if (_autoEQEnabled.value) applyCurrentEQSettings()
    }
    
    fun setDynamicAdjustmentEnabled(enabled: Boolean) {
        _dynamicAdjustment.value = enabled
        prefs.edit().putBoolean(PREF_DYNAMIC_ADJUSTMENT, enabled).apply()
    }
    
    fun setLearningEnabled(enabled: Boolean) {
        _learningEnabled.value = enabled
        prefs.edit().putBoolean(PREF_LEARNING_ENABLED, enabled).apply()
    }
    
    fun setLoudnessCompensation(compensation: Float) {
        _loudnessCompensation.value = compensation.coerceIn(0.0f, 1.0f)
        prefs.edit().putFloat(PREF_LOUDNESS_COMPENSATION, _loudnessCompensation.value).apply()
        if (_autoEQEnabled.value) applyCurrentEQSettings()
    }
    
    fun setReferenceCurve(curve: ReferenceCurve) {
        _referenceCurve.value = curve
        prefs.edit().putString(PREF_REFERENCE_CURVE, curve.name).apply()
        if (_autoEQEnabled.value) applyCurrentEQSettings()
    }
    
    fun setAdaptationSpeed(speed: Float) {
        _adaptationSpeed.value = speed.coerceIn(0.1f, 1.0f)
        prefs.edit().putFloat(PREF_ADAPTATION_SPEED, _adaptationSpeed.value).apply()
    }
    
    fun setFrequencySensitivity(sensitivity: Float) {
        _frequencySensitivity.value = sensitivity.coerceIn(0.1f, 1.0f)
        prefs.edit().putFloat(PREF_FREQUENCY_SENSITIVITY, _frequencySensitivity.value).apply()
    }
    
    // Main analysis function - called with audio samples
    fun analyzeAudioContent(samples: FloatArray, genre: String? = null) {
        if (!_autoEQEnabled.value) return
        
        try {
            // Perform spectral analysis
            performSpectralAnalysis(samples)
            
            // Detect or use provided genre
            val detectedGenre = genre ?: detectGenre(samples)
            _currentGenre.value = detectedGenre
            
            // Analyze tempo
            _detectedTempo.value = detectTempo(samples)
            
            // Calculate spectral balance
            _spectralBalance.value = calculateSpectralBalance()
            
            // Apply dynamic adjustments if enabled
            if (_dynamicAdjustment.value) {
                applyDynamicAdjustments(detectedGenre)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing audio content", e)
        }
    }
    
    private fun performSpectralAnalysis(samples: FloatArray) {
        // Apply window function (Hanning)
        val windowedSamples = applyHanningWindow(samples.take(FFT_SIZE).toFloatArray())
        
        // Perform FFT (simplified - in real implementation would use actual FFT)
        frequencyAnalysis = performFFT(windowedSamples)
        
        // Calculate spectral features
        spectralCentroid = calculateSpectralCentroid(frequencyAnalysis)
        spectralSpread = calculateSpectralSpread(frequencyAnalysis, spectralCentroid)
        spectralRolloff = calculateSpectralRolloff(frequencyAnalysis)
        zeroCrossingRate = calculateZeroCrossingRate(samples)
        mfcc = calculateMFCC(frequencyAnalysis)
    }
    
    private fun applyHanningWindow(samples: FloatArray): FloatArray {
        return samples.mapIndexed { i, sample ->
            val window = 0.5f * (1 - cos(2 * PI * i / (samples.size - 1))).toFloat()
            sample * window
        }.toFloatArray()
    }
    
    private fun performFFT(samples: FloatArray): FloatArray {
        // Simplified FFT - in real implementation would use proper FFT library
        val fftResult = FloatArray(samples.size / 2)
        for (k in fftResult.indices) {
            var real = 0.0f
            var imag = 0.0f
            for (n in samples.indices) {
                val angle = -2.0 * PI * k * n / samples.size
                real += samples[n] * cos(angle).toFloat()
                imag += samples[n] * sin(angle).toFloat()
            }
            fftResult[k] = sqrt(real * real + imag * imag)
        }
        return fftResult
    }
    
    private fun calculateSpectralCentroid(spectrum: FloatArray): Float {
        var weightedSum = 0.0f
        var magnitudeSum = 0.0f
        
        for (i in spectrum.indices) {
            val frequency = i * SAMPLE_RATE / (2 * spectrum.size)
            weightedSum += frequency * spectrum[i]
            magnitudeSum += spectrum[i]
        }
        
        return if (magnitudeSum > 0) weightedSum / magnitudeSum else 0.0f
    }
    
    private fun calculateSpectralSpread(spectrum: FloatArray, centroid: Float): Float {
        var weightedSum = 0.0f
        var magnitudeSum = 0.0f
        
        for (i in spectrum.indices) {
            val frequency = i * SAMPLE_RATE / (2 * spectrum.size)
            val deviation = frequency - centroid
            weightedSum += deviation * deviation * spectrum[i]
            magnitudeSum += spectrum[i]
        }
        
        return if (magnitudeSum > 0) sqrt(weightedSum / magnitudeSum) else 0.0f
    }
    
    private fun calculateSpectralRolloff(spectrum: FloatArray): Float {
        val totalEnergy = spectrum.sum()
        var cumulativeEnergy = 0.0f
        val threshold = totalEnergy * 0.85f
        
        for (i in spectrum.indices) {
            cumulativeEnergy += spectrum[i]
            if (cumulativeEnergy >= threshold) {
                return i * SAMPLE_RATE / (2 * spectrum.size)
            }
        }
        return SAMPLE_RATE / 2
    }
    
    private fun calculateZeroCrossingRate(samples: FloatArray): Float {
        var crossings = 0
        for (i in 1 until samples.size) {
            if ((samples[i] >= 0) != (samples[i - 1] >= 0)) {
                crossings++
            }
        }
        return crossings.toFloat() / samples.size
    }
    
    private fun calculateMFCC(spectrum: FloatArray): FloatArray {
        // Simplified MFCC calculation
        val mfcc = FloatArray(13)
        val melBanks = createMelFilterBanks(spectrum.size)
        
        for (i in mfcc.indices) {
            var sum = 0.0f
            for (j in spectrum.indices) {
                sum += spectrum[j] * melBanks[i][j]
            }
            mfcc[i] = ln(sum + 1e-10f)
        }
        
        return mfcc
    }
    
    private fun createMelFilterBanks(spectrumSize: Int): Array<FloatArray> {
        // Simplified mel filter bank creation
        val numBanks = 13
        val banks = Array(numBanks) { FloatArray(spectrumSize) }
        
        for (bank in 0 until numBanks) {
            val centerFreq = 1000.0f * (bank + 1) / numBanks
            val centerBin = (centerFreq * spectrumSize * 2 / SAMPLE_RATE).toInt()
            
            for (i in banks[bank].indices) {
                val distance = abs(i - centerBin)
                banks[bank][i] = max(0.0f, 1.0f - distance / (spectrumSize / numBanks))
            }
        }
        
        return banks
    }
    
    private fun detectGenre(@Suppress("UNUSED_PARAMETER") samples: FloatArray): String {
        // Simplified genre detection based on audio features
        val features = GenreFeatures(
            spectralCentroid = spectralCentroid,
            spectralSpread = spectralSpread,
            zeroCrossingRate = zeroCrossingRate,
            tempo = _detectedTempo.value,
            bassEnergy = frequencyAnalysis.take(20).sum(),
            highFreqEnergy = frequencyAnalysis.takeLast(20).sum()
        )
        
        return classifyGenre(features)
    }
    
    private fun classifyGenre(features: GenreFeatures): String {
        // Rule-based genre classification (simplified)
        return when {
            features.bassEnergy > 0.7f && features.tempo > 120 -> "Electronic"
            features.spectralCentroid < 2000 && features.bassEnergy > 0.5f -> "Hip-Hop"
            features.tempo > 140 && features.highFreqEnergy > 0.6f -> "Rock"
            features.spectralSpread > 3000 && features.zeroCrossingRate > 0.1f -> "Metal"
            features.spectralCentroid > 3000 && features.tempo < 100 -> "Classical"
            features.tempo < 80 && features.spectralCentroid < 2500 -> "Jazz"
            features.tempo in 90f..130f -> "Pop"
            else -> "Unknown"
        }
    }
    
    private fun detectTempo(samples: FloatArray): Float {
        // Simplified tempo detection using autocorrelation
        val hopSize = 512
        var bestTempo = 120.0f
        var maxCorrelation = 0.0f
        
        for (tempo in 60..180 step 2) {
            val samplesPerBeat = (60.0f * SAMPLE_RATE / tempo).toInt()
            var correlation = 0.0f
            var count = 0
            
            for (i in 0 until samples.size - samplesPerBeat step hopSize) {
                correlation += samples[i] * samples[i + samplesPerBeat]
                count++
            }
            
            correlation /= count
            if (correlation > maxCorrelation) {
                maxCorrelation = correlation
                bestTempo = tempo.toFloat()
            }
        }
        
        return bestTempo
    }
    
    private fun calculateSpectralBalance(): SpectralBalance {
        val totalEnergy = frequencyAnalysis.sum()
        if (totalEnergy == 0.0f) return SpectralBalance()
        
        val bassEnd = (200 * frequencyAnalysis.size * 2 / SAMPLE_RATE).toInt()
        val midStart = (200 * frequencyAnalysis.size * 2 / SAMPLE_RATE).toInt()
        val midEnd = (4000 * frequencyAnalysis.size * 2 / SAMPLE_RATE).toInt()
        val trebleStart = (4000 * frequencyAnalysis.size * 2 / SAMPLE_RATE).toInt()
        
        val bassEnergy = frequencyAnalysis.take(bassEnd).sum() / totalEnergy
        val midEnergy = frequencyAnalysis.drop(midStart).take(midEnd - midStart).sum() / totalEnergy
        val trebleEnergy = frequencyAnalysis.drop(trebleStart).sum() / totalEnergy
        
        return SpectralBalance(bassEnergy, midEnergy, trebleEnergy)
    }
    
    private fun applyDynamicAdjustments(genre: String) {
        if (!_autoEQEnabled.value) return
        
        try {
            equalizer?.let { eq ->
                val numBands = eq.numberOfBands.toInt()
                val adjustments = FloatArray(numBands) { 0.0f }
                
                // Get base genre profile
                val genreProfile = genreProfiles[genre] ?: genreProfiles["Unknown"]!!
                
                // Apply genre-based adjustments
                if (_genreOptimization.value) {
                    for (i in 0 until min(numBands, genreProfile.bandAdjustments.size)) {
                        adjustments[i] += genreProfile.bandAdjustments[i]
                    }
                }
                
                // Apply reference curve
                val referenceCurveAdjustments = getReferenceCurveAdjustments(_referenceCurve.value, numBands)
                for (i in 0 until numBands) {
                    adjustments[i] += referenceCurveAdjustments[i]
                }
                
                // Apply loudness compensation
                val loudnessAdjustments = calculateLoudnessCompensation(numBands)
                for (i in 0 until numBands) {
                    adjustments[i] += loudnessAdjustments[i] * _loudnessCompensation.value
                }
                
                // Apply spectral balance corrections
                val spectralAdjustments = calculateSpectralBalanceAdjustments(numBands)
                for (i in 0 until numBands) {
                    adjustments[i] += spectralAdjustments[i] * _frequencySensitivity.value
                }
                
                // Smooth adjustments with adaptation speed
                val currentAdjustments = _eqAdjustments.value
                if (currentAdjustments.size == numBands) {
                    val smoothingFactor = 1.0f - _adaptationSpeed.value
                    for (i in 0 until numBands) {
                        adjustments[i] = currentAdjustments[i] * smoothingFactor + 
                                       adjustments[i] * _adaptationSpeed.value
                    }
                }
                
                // Apply adjustments to equalizer
                for (i in 0 until numBands) {
                    val levelMb = (adjustments[i] * 100).toInt()
                    val levelShort = levelMb.toShort()
                    eq.setBandLevel(i.toShort(), levelShort.coerceIn(eq.getBandLevelRange()[0], eq.getBandLevelRange()[1]))
                }
                
                _eqAdjustments.value = adjustments
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error applying dynamic adjustments", e)
        }
    }
    
    private fun getReferenceCurveAdjustments(curve: ReferenceCurve, numBands: Int): FloatArray {
        return when (curve) {
            ReferenceCurve.FLAT -> FloatArray(numBands) { 0.0f }
            ReferenceCurve.HARMAN_TARGET -> {
                // Simplified Harman target curve
                val adjustments = FloatArray(numBands)
                for (i in 0 until numBands) {
                    val frequency = getEQBandFrequency(i, numBands)
                    adjustments[i] = when {
                        frequency < 100 -> 2.0f
                        frequency < 1000 -> 0.0f
                        frequency < 3000 -> -2.0f
                        frequency < 8000 -> 1.0f
                        else -> -1.0f
                    }
                }
                adjustments
            }
            ReferenceCurve.DIFFUSE_FIELD -> {
                // Simplified diffuse field curve
                val adjustments = FloatArray(numBands)
                for (i in 0 until numBands) {
                    val frequency = getEQBandFrequency(i, numBands)
                    adjustments[i] = when {
                        frequency < 1000 -> 0.0f
                        frequency < 4000 -> 3.0f * log10(frequency / 1000)
                        else -> 1.5f
                    }
                }
                adjustments
            }
        }
    }
    
    private fun calculateLoudnessCompensation(numBands: Int): FloatArray {
        // ISO 226 equal-loudness contour approximation
        val adjustments = FloatArray(numBands)
        for (i in 0 until numBands) {
            val frequency = getEQBandFrequency(i, numBands)
            adjustments[i] = when {
                frequency < 100 -> 5.0f
                frequency < 1000 -> -2.0f * log10(frequency / 100)
                frequency < 4000 -> 0.0f
                else -> 1.0f
            }
        }
        return adjustments
    }
    
    private fun calculateSpectralBalanceAdjustments(numBands: Int): FloatArray {
        val balance = _spectralBalance.value
        val adjustments = FloatArray(numBands)
        
        for (i in 0 until numBands) {
            val frequency = getEQBandFrequency(i, numBands)
            adjustments[i] = when {
                frequency < 250 -> (0.33f - balance.bassEnergy) * 6.0f
                frequency < 4000 -> (0.33f - balance.midEnergy) * 4.0f
                else -> (0.33f - balance.trebleEnergy) * 5.0f
            }
        }
        
        return adjustments
    }
    
    private fun getEQBandFrequency(bandIndex: Int, numBands: Int): Float {
        // Logarithmic frequency distribution from 20Hz to 20kHz
        val minFreq = 20.0f
        val maxFreq = 20000.0f
        val logMin = log10(minFreq)
        val logMax = log10(maxFreq)
        val logFreq = logMin + (logMax - logMin) * bandIndex / (numBands - 1)
        return 10.0f.pow(logFreq)
    }
    
    private fun applyCurrentEQSettings() {
        if (_autoEQEnabled.value) {
            applyDynamicAdjustments(_currentGenre.value)
        }
    }
    
    // User interaction learning
    fun recordUserAdjustment(bandIndex: Int, adjustment: Float, genre: String) {
        if (!_learningEnabled.value) return
        
        val userAdjustment = UserAdjustment(
            genre = genre,
            bandIndex = bandIndex,
            adjustment = adjustment,
            timestamp = System.currentTimeMillis()
        )
        
        userAdjustments.add(userAdjustment)
        
        // Update genre profile based on user feedback
        updateGenreProfile(genre, userAdjustment)
        
        // Limit stored adjustments to prevent memory issues
        if (userAdjustments.size > 1000) {
            userAdjustments.removeAt(0)
        }
    }
    
    private fun updateGenreProfile(genre: String, adjustment: UserAdjustment) {
        val profile = genreProfiles.getOrPut(genre) { 
            EQProfile(genre, FloatArray(10) { 0.0f }) 
        }
        
        if (adjustment.bandIndex < profile.bandAdjustments.size) {
            // Apply exponential moving average for learning
            val learningRate = 0.1f
            profile.bandAdjustments[adjustment.bandIndex] = 
                profile.bandAdjustments[adjustment.bandIndex] * (1 - learningRate) +
                adjustment.adjustment * learningRate
        }
    }
    
    private fun initializeGenreProfiles() {
        // Initialize default genre profiles
        genreProfiles["Rock"] = EQProfile("Rock", floatArrayOf(
            2.0f, 1.0f, -1.0f, 1.0f, 2.0f, 2.0f, 1.0f, 2.0f, 3.0f, 2.0f
        ))
        
        genreProfiles["Pop"] = EQProfile("Pop", floatArrayOf(
            1.0f, 0.5f, 0.0f, 0.5f, 1.0f, 1.0f, 1.5f, 1.0f, 0.5f, 0.0f
        ))
        
        genreProfiles["Classical"] = EQProfile("Classical", floatArrayOf(
            0.0f, -0.5f, -1.0f, 0.0f, 0.5f, 1.0f, 1.5f, 2.0f, 1.5f, 1.0f
        ))
        
        genreProfiles["Jazz"] = EQProfile("Jazz", floatArrayOf(
            1.5f, 1.0f, 0.0f, 0.5f, 1.0f, 1.5f, 2.0f, 1.5f, 1.0f, 0.5f
        ))
        
        genreProfiles["Electronic"] = EQProfile("Electronic", floatArrayOf(
            3.0f, 2.0f, 0.0f, -0.5f, 1.0f, 2.0f, 3.0f, 4.0f, 3.0f, 2.0f
        ))
        
        genreProfiles["Hip-Hop"] = EQProfile("Hip-Hop", floatArrayOf(
            4.0f, 3.0f, 1.0f, 0.0f, 1.0f, 1.5f, 2.0f, 2.5f, 2.0f, 1.0f
        ))
        
        genreProfiles["Metal"] = EQProfile("Metal", floatArrayOf(
            2.0f, 1.0f, -2.0f, 0.0f, 2.0f, 3.0f, 2.0f, 3.0f, 4.0f, 3.0f
        ))
        
        genreProfiles["Unknown"] = EQProfile("Unknown", FloatArray(10) { 0.0f })
    }
    
    private fun loadSettings() {
        _autoEQEnabled.value = prefs.getBoolean(PREF_AUTO_EQ_ENABLED, false)
        _genreOptimization.value = prefs.getBoolean(PREF_GENRE_OPTIMIZATION, true)
        _dynamicAdjustment.value = prefs.getBoolean(PREF_DYNAMIC_ADJUSTMENT, true)
        _learningEnabled.value = prefs.getBoolean(PREF_LEARNING_ENABLED, true)
        _loudnessCompensation.value = prefs.getFloat(PREF_LOUDNESS_COMPENSATION, 0.5f)
        
        val referenceCurveName = prefs.getString(PREF_REFERENCE_CURVE, ReferenceCurve.FLAT.name)
        _referenceCurve.value = ReferenceCurve.valueOf(referenceCurveName ?: ReferenceCurve.FLAT.name)
        
        _adaptationSpeed.value = prefs.getFloat(PREF_ADAPTATION_SPEED, 0.5f)
        _frequencySensitivity.value = prefs.getFloat(PREF_FREQUENCY_SENSITIVITY, 0.7f)
    }
}

enum class ReferenceCurve {
    FLAT,
    HARMAN_TARGET,
    DIFFUSE_FIELD
}

data class EQProfile(
    val genre: String,
    val bandAdjustments: FloatArray
)

data class UserAdjustment(
    val genre: String,
    val bandIndex: Int,
    val adjustment: Float,
    val timestamp: Long
)

data class SpectralBalance(
    val bassEnergy: Float = 0.33f,
    val midEnergy: Float = 0.33f,
    val trebleEnergy: Float = 0.33f
)

data class GenreFeatures(
    val spectralCentroid: Float,
    val spectralSpread: Float,
    val zeroCrossingRate: Float,
    val tempo: Float,
    val bassEnergy: Float,
    val highFreqEnergy: Float
)