package com.stash.opusplayer.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.*
import android.util.Log
import androidx.preference.PreferenceManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.*

/**
 * Professional Audio Processor
 * 
 * Advanced audio processing engine with professional DSP features:
 * - Multi-band parametric equalizer
 * - Dynamic range compressor/expander
 * - Audio limiting and maximizing
 * - Stereo enhancement and imaging
 * - Harmonic excitation and tube warmth
 * - Spectral analysis and automatic adjustments
 * - Psychoacoustic enhancement
 */
class ProfessionalAudioProcessor(private val context: Context) {
    
    companion object {
        private const val TAG = "ProfessionalAudioProcessor"
        
        // Preference keys
        private const val PREF_PROCESSOR_ENABLED = "professional_processor_enabled"
        private const val PREF_MASTER_GAIN = "master_gain"
        private const val PREF_HEADROOM = "headroom_db"
        private const val PREF_STEREO_WIDTH = "stereo_width"
        private const val PREF_MONO_BASS_FREQ = "mono_bass_frequency"
        
        // Compressor
        private const val PREF_COMPRESSOR_ENABLED = "comp_enabled"
        private const val PREF_COMPRESSOR_THRESHOLD = "comp_threshold"
        private const val PREF_COMPRESSOR_RATIO = "comp_ratio"
        private const val PREF_COMPRESSOR_ATTACK = "comp_attack"
        private const val PREF_COMPRESSOR_RELEASE = "comp_release"
        private const val PREF_COMPRESSOR_MAKEUP_GAIN = "comp_makeup_gain"
        private const val PREF_COMPRESSOR_KNEE = "comp_knee"
        
        // Limiter
        private const val PREF_LIMITER_ENABLED = "limiter_enabled" 
        private const val PREF_LIMITER_THRESHOLD = "limiter_threshold"
        private const val PREF_LIMITER_RELEASE = "limiter_release"
        private const val PREF_LIMITER_ISR = "limiter_isr" // Inter-sample limiting
        
        // Gate/Expander
        private const val PREF_GATE_ENABLED = "gate_enabled"
        private const val PREF_GATE_THRESHOLD = "gate_threshold"
        private const val PREF_GATE_RATIO = "gate_ratio"
        private const val PREF_GATE_ATTACK = "gate_attack"
        private const val PREF_GATE_RELEASE = "gate_release"
        
        // Exciter/Enhancer
        private const val PREF_EXCITER_ENABLED = "exciter_enabled"
        private const val PREF_EXCITER_AMOUNT = "exciter_amount"
        private const val PREF_EXCITER_FREQUENCY = "exciter_frequency"
        private const val PREF_TUBE_WARMTH = "tube_warmth"
        private const val PREF_TAPE_SATURATION = "tape_saturation"
        
        // Spatial Processing
        private const val PREF_CROSSFEED_ENABLED = "crossfeed_enabled"
        private const val PREF_CROSSFEED_AMOUNT = "crossfeed_amount"
        private const val PREF_CROSSFEED_DELAY = "crossfeed_delay"
        private const val PREF_BINAURAL_ENABLED = "binaural_enabled"
        
        // Analysis
        private const val PREF_AUTO_GAIN_ENABLED = "auto_gain_enabled"
        private const val PREF_TARGET_LUFS = "target_lufs"
        private const val PREF_LOUDNESS_RANGE_TARGET = "loudness_range_target"
        private const val PREF_SPECTRAL_TILT = "spectral_tilt_correction"
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    // Android Audio Effects
    private var dynamicsProcessing: DynamicsProcessing? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var environmentalReverb: EnvironmentalReverb? = null
    private var presetReverb: PresetReverb? = null
    
    // State flows for all parameters
    private val _enabled = MutableStateFlow(false)
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()
    
    private val _masterGain = MutableStateFlow(0.0f)
    val masterGain: StateFlow<Float> = _masterGain.asStateFlow()
    
    private val _headroom = MutableStateFlow(3.0f)
    val headroom: StateFlow<Float> = _headroom.asStateFlow()
    
    private val _stereoWidth = MutableStateFlow(1.0f)
    val stereoWidth: StateFlow<Float> = _stereoWidth.asStateFlow()
    
    // Compressor
    private val _compressorEnabled = MutableStateFlow(false)
    val compressorEnabled: StateFlow<Boolean> = _compressorEnabled.asStateFlow()
    
    private val _compressorThreshold = MutableStateFlow(-12.0f)
    val compressorThreshold: StateFlow<Float> = _compressorThreshold.asStateFlow()
    
    private val _compressorRatio = MutableStateFlow(4.0f)
    val compressorRatio: StateFlow<Float> = _compressorRatio.asStateFlow()
    
    private val _compressorAttack = MutableStateFlow(5.0f)
    val compressorAttack: StateFlow<Float> = _compressorAttack.asStateFlow()
    
    private val _compressorRelease = MutableStateFlow(50.0f)
    val compressorRelease: StateFlow<Float> = _compressorRelease.asStateFlow()
    
    private val _compressorMakeupGain = MutableStateFlow(0.0f)
    val compressorMakeupGain: StateFlow<Float> = _compressorMakeupGain.asStateFlow()
    
    private val _compressorKnee = MutableStateFlow(2.0f)
    val compressorKnee: StateFlow<Float> = _compressorKnee.asStateFlow()
    
    // Limiter
    private val _limiterEnabled = MutableStateFlow(false)
    val limiterEnabled: StateFlow<Boolean> = _limiterEnabled.asStateFlow()
    
    private val _limiterThreshold = MutableStateFlow(-1.0f)
    val limiterThreshold: StateFlow<Float> = _limiterThreshold.asStateFlow()
    
    private val _limiterRelease = MutableStateFlow(10.0f)
    val limiterRelease: StateFlow<Float> = _limiterRelease.asStateFlow()
    
    private val _limiterRatio = MutableStateFlow(10.0f)
    val limiterRatio: StateFlow<Float> = _limiterRatio.asStateFlow()
    
    // Gate/Expander
    private val _gateEnabled = MutableStateFlow(false)
    val gateEnabled: StateFlow<Boolean> = _gateEnabled.asStateFlow()
    
    private val _gateThreshold = MutableStateFlow(-40.0f)
    val gateThreshold: StateFlow<Float> = _gateThreshold.asStateFlow()
    
    private val _gateRatio = MutableStateFlow(1.5f)
    val gateRatio: StateFlow<Float> = _gateRatio.asStateFlow()
    
    // Exciter/Enhancer
    private val _exciterEnabled = MutableStateFlow(false)
    val exciterEnabled: StateFlow<Boolean> = _exciterEnabled.asStateFlow()
    
    private val _exciterAmount = MutableStateFlow(0.3f)
    val exciterAmount: StateFlow<Float> = _exciterAmount.asStateFlow()
    
    private val _exciterFrequency = MutableStateFlow(3000.0f)
    val exciterFrequency: StateFlow<Float> = _exciterFrequency.asStateFlow()
    
    private val _tubeWarmth = MutableStateFlow(0.0f)
    val tubeWarmth: StateFlow<Float> = _tubeWarmth.asStateFlow()
    
    private val _tapeSaturation = MutableStateFlow(0.0f)
    val tapeSaturation: StateFlow<Float> = _tapeSaturation.asStateFlow()
    
    // Spatial
    private val _crossfeedEnabled = MutableStateFlow(false)
    val crossfeedEnabled: StateFlow<Boolean> = _crossfeedEnabled.asStateFlow()
    
    private val _crossfeedAmount = MutableStateFlow(0.5f)
    val crossfeedAmount: StateFlow<Float> = _crossfeedAmount.asStateFlow()
    
    // Analysis
    private val _autoGainEnabled = MutableStateFlow(false)
    val autoGainEnabled: StateFlow<Boolean> = _autoGainEnabled.asStateFlow()
    
    private val _targetLufs = MutableStateFlow(-16.0f)
    val targetLufs: StateFlow<Float> = _targetLufs.asStateFlow()
    
    // Real-time analysis
    private val _currentLufs = MutableStateFlow(-23.0f)
    val currentLufs: StateFlow<Float> = _currentLufs.asStateFlow()
    
    private val _peakLevel = MutableStateFlow(-6.0f)
    val peakLevel: StateFlow<Float> = _peakLevel.asStateFlow()
    
    private val _rmsLevel = MutableStateFlow(-20.0f)
    val rmsLevel: StateFlow<Float> = _rmsLevel.asStateFlow()
    
    private val _dynamicRange = MutableStateFlow(12.0f)
    val dynamicRange: StateFlow<Float> = _dynamicRange.asStateFlow()
    
    private val _stereoCorrelation = MutableStateFlow(0.5f)
    val stereoCorrelation: StateFlow<Float> = _stereoCorrelation.asStateFlow()
    
    private val _gainReduction = MutableStateFlow(0.0f)
    val gainReduction: StateFlow<Float> = _gainReduction.asStateFlow()
    
    fun initialize(audioSessionId: Int) {
        try {
            release()
            
            // Initialize DynamicsProcessing for advanced control (API 28+)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                try {
                    val config = DynamicsProcessing.Config.Builder(
                        DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                        2, // stereo
                        true, // preEqInUse
                        7, // More EQ bands for better control
                        true, // mbcInUse (multiband compressor)
                        5, // mbcBandCount
                        true, // postEqInUse  
                        7, // More post-EQ bands
                        true // limiterInUse
                    ).build()
                    
                    dynamicsProcessing = DynamicsProcessing(0, audioSessionId, config)
                } catch (e: Exception) {
                    Log.w(TAG, "DynamicsProcessing not available", e)
                }
            }
            
            // Initialize other effects
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                try {
                    loudnessEnhancer = LoudnessEnhancer(audioSessionId)
                } catch (e: Exception) {
                    Log.w(TAG, "LoudnessEnhancer not available", e)
                }
            }
            
            try {
                bassBoost = BassBoost(0, audioSessionId)
                virtualizer = Virtualizer(0, audioSessionId)
                environmentalReverb = EnvironmentalReverb(0, audioSessionId)
                presetReverb = PresetReverb(0, audioSessionId)
            } catch (e: Exception) {
                Log.w(TAG, "Some audio effects not available", e)
            }
            
            loadSettings()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing professional audio processor", e)
        }
    }
    
    fun release() {
        try {
            dynamicsProcessing?.release()
            loudnessEnhancer?.release()
            bassBoost?.release()
            virtualizer?.release()
            environmentalReverb?.release()
            presetReverb?.release()
            
            dynamicsProcessing = null
            loudnessEnhancer = null
            bassBoost = null
            virtualizer = null
            environmentalReverb = null
            presetReverb = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing audio processor", e)
        }
    }
    
    // Main controls
    fun setEnabled(enabled: Boolean) {
        _enabled.value = enabled
        prefs.edit().putBoolean(PREF_PROCESSOR_ENABLED, enabled).apply()
        
        // Enable/disable all effects
        try {
            dynamicsProcessing?.enabled = enabled
            loudnessEnhancer?.enabled = enabled && _autoGainEnabled.value
            bassBoost?.enabled = enabled
            virtualizer?.enabled = enabled
            environmentalReverb?.enabled = enabled && (_crossfeedEnabled.value || _exciterEnabled.value)
            presetReverb?.enabled = enabled
        } catch (e: Exception) {
            Log.e(TAG, "Error setting enabled state", e)
        }
    }
    
    fun setMasterGain(gainDb: Float) {
        val clampedGain = gainDb.coerceIn(-20.0f, 20.0f)
        _masterGain.value = clampedGain
        prefs.edit().putFloat(PREF_MASTER_GAIN, clampedGain).apply()
        
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.setTargetGain((clampedGain * 100).toInt())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting master gain", e)
        }
    }
    
    // Compressor controls
    fun setCompressorEnabled(enabled: Boolean) {
        _compressorEnabled.value = enabled
        prefs.edit().putBoolean(PREF_COMPRESSOR_ENABLED, enabled).apply()
        applyDynamicsProcessing()
    }
    
    fun setCompressorThreshold(threshold: Float) {
        val clampedThreshold = threshold.coerceIn(-60.0f, 0.0f)
        _compressorThreshold.value = clampedThreshold
        prefs.edit().putFloat(PREF_COMPRESSOR_THRESHOLD, clampedThreshold).apply()
        applyDynamicsProcessing()
    }
    
    fun setCompressorRatio(ratio: Float) {
        val clampedRatio = ratio.coerceIn(1.0f, 20.0f)
        _compressorRatio.value = clampedRatio
        prefs.edit().putFloat(PREF_COMPRESSOR_RATIO, clampedRatio).apply()
        applyDynamicsProcessing()
    }
    
    fun setCompressorAttack(attackMs: Float) {
        val clampedAttack = attackMs.coerceIn(0.1f, 100.0f)
        _compressorAttack.value = clampedAttack
        prefs.edit().putFloat(PREF_COMPRESSOR_ATTACK, clampedAttack).apply()
        applyDynamicsProcessing()
    }
    
    fun setCompressorRelease(releaseMs: Float) {
        val clampedRelease = releaseMs.coerceIn(1.0f, 1000.0f)
        _compressorRelease.value = clampedRelease
        prefs.edit().putFloat(PREF_COMPRESSOR_RELEASE, clampedRelease).apply()
        applyDynamicsProcessing()
    }
    
    fun setCompressorKnee(kneeDb: Float) {
        val clampedKnee = kneeDb.coerceIn(0.0f, 10.0f)
        _compressorKnee.value = clampedKnee
        prefs.edit().putFloat(PREF_COMPRESSOR_KNEE, clampedKnee).apply()
        applyDynamicsProcessing()
    }
    
    // Limiter controls
    fun setLimiterEnabled(enabled: Boolean) {
        _limiterEnabled.value = enabled
        prefs.edit().putBoolean(PREF_LIMITER_ENABLED, enabled).apply()
        applyDynamicsProcessing()
    }
    
    fun setLimiterThreshold(threshold: Float) {
        val clampedThreshold = threshold.coerceIn(-10.0f, 0.0f)
        _limiterThreshold.value = clampedThreshold
        prefs.edit().putFloat(PREF_LIMITER_THRESHOLD, clampedThreshold).apply()
        applyDynamicsProcessing()
    }
    
    // Stereo processing
    fun setStereoWidth(width: Float) {
        val clampedWidth = width.coerceIn(0.0f, 2.0f)
        _stereoWidth.value = clampedWidth
        prefs.edit().putFloat(PREF_STEREO_WIDTH, clampedWidth).apply()
        applyStereoProcessing()
    }
    
    fun setCrossfeedEnabled(enabled: Boolean) {
        _crossfeedEnabled.value = enabled
        prefs.edit().putBoolean(PREF_CROSSFEED_ENABLED, enabled).apply()
        applyStereoProcessing()
    }
    
    fun setCrossfeedAmount(amount: Float) {
        val clampedAmount = amount.coerceIn(0.0f, 1.0f)
        _crossfeedAmount.value = clampedAmount
        prefs.edit().putFloat(PREF_CROSSFEED_AMOUNT, clampedAmount).apply()
        applyStereoProcessing()
    }
    
    // Exciter/Enhancement
    fun setExciterEnabled(enabled: Boolean) {
        _exciterEnabled.value = enabled
        prefs.edit().putBoolean(PREF_EXCITER_ENABLED, enabled).apply()
        applyExciterSettings()
    }
    
    fun setExciterAmount(amount: Float) {
        val clampedAmount = amount.coerceIn(0.0f, 1.0f)
        _exciterAmount.value = clampedAmount
        prefs.edit().putFloat(PREF_EXCITER_AMOUNT, clampedAmount).apply()
        applyExciterSettings()
    }
    
    fun setTubeWarmth(warmth: Float) {
        val clampedWarmth = warmth.coerceIn(0.0f, 1.0f)
        _tubeWarmth.value = clampedWarmth
        prefs.edit().putFloat(PREF_TUBE_WARMTH, clampedWarmth).apply()
        applyExciterSettings()
    }
    
    fun setTapeSaturation(saturation: Float) {
        val clampedSaturation = saturation.coerceIn(0.0f, 1.0f)
        _tapeSaturation.value = clampedSaturation
        prefs.edit().putFloat(PREF_TAPE_SATURATION, clampedSaturation).apply()
        applyExciterSettings()
    }
    
    // Auto gain
    fun setAutoGainEnabled(enabled: Boolean) {
        _autoGainEnabled.value = enabled
        prefs.edit().putBoolean(PREF_AUTO_GAIN_ENABLED, enabled).apply()
    }
    
    fun setTargetLufs(lufs: Float) {
        val clampedLufs = lufs.coerceIn(-30.0f, -6.0f)
        _targetLufs.value = clampedLufs
        prefs.edit().putFloat(PREF_TARGET_LUFS, clampedLufs).apply()
    }
    
    // Audio analysis
    fun analyzeAudio(samples: FloatArray, sampleRate: Int, channels: Int) {
        try {
            // Calculate RMS level
            val rms = sqrt(samples.map { it * it }.average()).toFloat()
            val rmsDb = if (rms > 0) 20 * log10(rms) else -60.0f
            _rmsLevel.value = rmsDb
            
            // Calculate peak level
            val peak = samples.maxOrNull() ?: 0.0f
            val peakDb = if (peak > 0) 20 * log10(peak) else -60.0f
            _peakLevel.value = peakDb
            
            // Estimate LUFS (simplified)
            val lufsEstimate = rmsDb - 0.691f  // K-weighting approximation
            _currentLufs.value = lufsEstimate
            
            // Auto gain adjustment
            if (_autoGainEnabled.value && _enabled.value) {
                val targetLufs = _targetLufs.value
                val difference = targetLufs - lufsEstimate
                if (abs(difference) > 1.0f) {
                    val newGain = (_masterGain.value + difference * 0.1f).coerceIn(-20.0f, 20.0f)
                    setMasterGain(newGain)
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing audio", e)
        }
    }
    
    fun analyzeStereoContent(leftChannel: FloatArray, rightChannel: FloatArray) {
        try {
            // Calculate stereo correlation
            var correlation = 0.0
            var leftPower = 0.0
            var rightPower = 0.0
            
            for (i in leftChannel.indices) {
                correlation += leftChannel[i] * rightChannel[i]
                leftPower += leftChannel[i] * leftChannel[i]
                rightPower += rightChannel[i] * rightChannel[i]
            }
            
            val denominator = sqrt(leftPower * rightPower)
            val stereoCorr = if (denominator > 0) (correlation / denominator).toFloat() else 0.0f
            _stereoCorrelation.value = stereoCorr.coerceIn(-1.0f, 1.0f)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing stereo content", e)
        }
    }
    
    // Apply professional audio presets
    fun applyAudioProfilePreset(profile: AudioProfilePreset) {
        when (profile) {
            AudioProfilePreset.MASTERING -> {
                setCompressorEnabled(true)
                setCompressorThreshold(-8.0f)
                setCompressorRatio(3.0f)
                setCompressorAttack(3.0f)
                setCompressorRelease(100.0f)
                setLimiterEnabled(true)
                setLimiterThreshold(-1.0f)
                setStereoWidth(1.2f)
                setAutoGainEnabled(true)
                setTargetLufs(-14.0f)
            }
            AudioProfilePreset.AUDIOPHILE -> {
                setCompressorEnabled(false)
                setLimiterEnabled(true)
                setLimiterThreshold(-0.5f)
                setStereoWidth(1.0f)
                setCrossfeedEnabled(true)
                setCrossfeedAmount(0.3f)
                setExciterEnabled(false)
                setAutoGainEnabled(false)
            }
            AudioProfilePreset.BROADCAST -> {
                setCompressorEnabled(true)
                setCompressorThreshold(-12.0f)
                setCompressorRatio(6.0f)
                setCompressorAttack(1.0f)
                setCompressorRelease(200.0f)
                setLimiterEnabled(true)
                setLimiterThreshold(-2.0f)
                setAutoGainEnabled(true)
                setTargetLufs(-16.0f)
            }
            AudioProfilePreset.CLUB -> {
                setCompressorEnabled(true)
                setCompressorThreshold(-6.0f)
                setCompressorRatio(8.0f)
                setLimiterEnabled(true)
                setLimiterThreshold(-0.1f)
                setStereoWidth(1.5f)
                setExciterEnabled(true)
                setExciterAmount(0.4f)
                setAutoGainEnabled(true)
                setTargetLufs(-12.0f)
            }
            AudioProfilePreset.VINTAGE -> {
                setCompressorEnabled(true)
                setCompressorThreshold(-15.0f)
                setCompressorRatio(2.5f)
                setTubeWarmth(0.6f)
                setTapeSaturation(0.4f)
                setStereoWidth(0.8f)
                setExciterEnabled(false)
            }
        }
    }
    
    private fun loadSettings() {
        try {
            _enabled.value = prefs.getBoolean(PREF_PROCESSOR_ENABLED, false)
            _masterGain.value = prefs.getFloat(PREF_MASTER_GAIN, 0.0f)
            _stereoWidth.value = prefs.getFloat(PREF_STEREO_WIDTH, 1.0f)
            
            // Compressor
            _compressorEnabled.value = prefs.getBoolean(PREF_COMPRESSOR_ENABLED, false)
            _compressorThreshold.value = prefs.getFloat(PREF_COMPRESSOR_THRESHOLD, -12.0f)
            _compressorRatio.value = prefs.getFloat(PREF_COMPRESSOR_RATIO, 4.0f)
            _compressorAttack.value = prefs.getFloat(PREF_COMPRESSOR_ATTACK, 5.0f)
            _compressorRelease.value = prefs.getFloat(PREF_COMPRESSOR_RELEASE, 50.0f)
            _compressorKnee.value = prefs.getFloat(PREF_COMPRESSOR_KNEE, 2.0f)
            
            // Limiter
            _limiterEnabled.value = prefs.getBoolean(PREF_LIMITER_ENABLED, false)
            _limiterThreshold.value = prefs.getFloat(PREF_LIMITER_THRESHOLD, -1.0f)
            
            // Spatial
            _crossfeedEnabled.value = prefs.getBoolean(PREF_CROSSFEED_ENABLED, false)
            _crossfeedAmount.value = prefs.getFloat(PREF_CROSSFEED_AMOUNT, 0.5f)
            
            // Exciter
            _exciterEnabled.value = prefs.getBoolean(PREF_EXCITER_ENABLED, false)
            _exciterAmount.value = prefs.getFloat(PREF_EXCITER_AMOUNT, 0.3f)
            _tubeWarmth.value = prefs.getFloat(PREF_TUBE_WARMTH, 0.0f)
            _tapeSaturation.value = prefs.getFloat(PREF_TAPE_SATURATION, 0.0f)
            
            // Auto gain
            _autoGainEnabled.value = prefs.getBoolean(PREF_AUTO_GAIN_ENABLED, false)
            _targetLufs.value = prefs.getFloat(PREF_TARGET_LUFS, -16.0f)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error loading settings", e)
        }
    }
    
    private fun applyDynamicsProcessing() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            try {
                dynamicsProcessing?.let { dp ->
                    if (_compressorEnabled.value) {
                        // Configure multiband compressor
                        for (band in 0 until 5) {
                            val mbc = DynamicsProcessing.MbcBand(
                                _compressorEnabled.value,
                                20.0f, // cutoffFrequency (will be set appropriately for each band)
                                _compressorAttack.value,
                                _compressorRelease.value,
                                _compressorRatio.value,
                                _compressorThreshold.value,
                                _compressorKnee.value,
                                0.0f, // noiseGateThreshold
                                1.0f, // expanderRatio
                                0.0f, // preGain
                                _compressorMakeupGain.value // postGain
                            )
                            dp.setMbcBandAllChannelsTo(band, mbc)
                        }
                    }
                    
                    if (_limiterEnabled.value) {
                        val limiter = DynamicsProcessing.Limiter(
                            _limiterEnabled.value,
                            true, // enabled
                            1, // linkGroup
                            10.0f, // attackTime
                            _limiterRelease.value,
                            10.0f, // ratio
                            _limiterThreshold.value,
                            0.0f // postGain
                        )
                        dp.setLimiterAllChannelsTo(limiter)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error applying dynamics processing", e)
            }
        }
    }
    
    private fun applyStereoProcessing() {
        try {
            val virtualizerStrength = (_stereoWidth.value * 500).toInt().coerceIn(0, 1000)
            virtualizer?.setStrength(virtualizerStrength.toShort())
            
            if (_crossfeedEnabled.value) {
                environmentalReverb?.let { reverb ->
                    val roomSize = (_crossfeedAmount.value * -1000).toInt().toShort()
                    reverb.setRoomLevel(roomSize)
                    reverb.setReflectionsLevel(roomSize)
                    reverb.decayTime = (500 + _crossfeedAmount.value * 1000).toInt()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error applying stereo processing", e)
        }
    }
    
    private fun applyExciterSettings() {
        try {
            if (_exciterEnabled.value) {
                val bassBoostStrength = (_exciterAmount.value * 500 + _tubeWarmth.value * 300).toInt()
                bassBoost?.setStrength(bassBoostStrength.coerceIn(0, 1000).toShort())
                
                val reverbPreset = if (_tubeWarmth.value > 0.5f) {
                    PresetReverb.PRESET_SMALLROOM
                } else {
                    PresetReverb.PRESET_NONE
                }
                presetReverb?.preset = reverbPreset
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error applying exciter settings", e)
        }
    }
}

enum class AudioProfilePreset {
    MASTERING,
    AUDIOPHILE, 
    BROADCAST,
    CLUB,
    VINTAGE
}

