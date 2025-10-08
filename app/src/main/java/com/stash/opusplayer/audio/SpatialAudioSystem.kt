package com.stash.opusplayer.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.Virtualizer
import android.util.Log
import androidx.preference.PreferenceManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.*

/**
 * Spatial Audio System
 * 
 * Provides 3D spatial audio processing including:
 * - Binaural rendering for headphones
 * - Cross-feed for enhanced stereo imaging
 * - Virtual surround sound
 * - Room simulation
 * - Head-related transfer function (HRTF) simulation
 * - Distance and elevation modeling
 */
class SpatialAudioSystem(private val context: Context) {
    
    companion object {
        private const val TAG = "SpatialAudioSystem"
        
        // Preference keys
        private const val PREF_SPATIAL_ENABLED = "spatial_enabled"
        private const val PREF_BINAURAL_ENABLED = "binaural_enabled"
        private const val PREF_CROSSFEED_ENABLED = "crossfeed_enabled"
        private const val PREF_CROSSFEED_STRENGTH = "crossfeed_strength"
        private const val PREF_ROOM_SIZE = "room_size"
        private const val PREF_ROOM_REFLECTIONS = "room_reflections"
        private const val PREF_SURROUND_ENABLED = "surround_enabled"
        private const val PREF_SURROUND_ANGLE = "surround_angle"
        private const val PREF_HEAD_SIZE = "head_size"
        private const val PREF_DISTANCE_ATTENUATION = "distance_attenuation"
        private const val PREF_ELEVATION_ENABLED = "elevation_enabled"
        
        // HRTF simulation constants
        private const val DEFAULT_HEAD_RADIUS = 0.0875f // 8.75cm average head radius
        private const val SOUND_SPEED = 343.0f // m/s
        private const val SAMPLE_RATE = 44100f
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    // Android Audio Effects
    private var virtualizer: Virtualizer? = null
    
    // State flows for UI
    private val _spatialEnabled = MutableStateFlow(false)
    val spatialEnabled: StateFlow<Boolean> = _spatialEnabled.asStateFlow()
    
    private val _binauralEnabled = MutableStateFlow(false)
    val binauralEnabled: StateFlow<Boolean> = _binauralEnabled.asStateFlow()
    
    private val _crossfeedEnabled = MutableStateFlow(false)
    val crossfeedEnabled: StateFlow<Boolean> = _crossfeedEnabled.asStateFlow()
    
    private val _crossfeedStrength = MutableStateFlow(0.3f)
    val crossfeedStrength: StateFlow<Float> = _crossfeedStrength.asStateFlow()
    
    private val _roomSize = MutableStateFlow(0.5f)
    val roomSize: StateFlow<Float> = _roomSize.asStateFlow()
    
    private val _roomReflections = MutableStateFlow(0.3f)
    val roomReflections: StateFlow<Float> = _roomReflections.asStateFlow()
    
    private val _surroundEnabled = MutableStateFlow(false)
    val surroundEnabled: StateFlow<Boolean> = _surroundEnabled.asStateFlow()
    
    private val _surroundAngle = MutableStateFlow(90.0f)
    val surroundAngle: StateFlow<Float> = _surroundAngle.asStateFlow()
    
    private val _headSize = MutableStateFlow(1.0f)
    val headSize: StateFlow<Float> = _headSize.asStateFlow()
    
    private val _distanceAttenuation = MutableStateFlow(0.5f)
    val distanceAttenuation: StateFlow<Float> = _distanceAttenuation.asStateFlow()
    
    private val _elevationEnabled = MutableStateFlow(false)
    val elevationEnabled: StateFlow<Boolean> = _elevationEnabled.asStateFlow()
    
    // Audio position state
    private val _azimuth = MutableStateFlow(0.0f)
    val azimuth: StateFlow<Float> = _azimuth.asStateFlow()
    
    private val _elevation = MutableStateFlow(0.0f)
    val elevation: StateFlow<Float> = _elevation.asStateFlow()
    
    private val _distance = MutableStateFlow(1.0f)
    val distance: StateFlow<Float> = _distance.asStateFlow()
    
    fun initialize(audioSessionId: Int) {
        try {
            release()
            
            // Initialize Virtualizer for surround sound
            try {
                virtualizer = Virtualizer(0, audioSessionId).apply {
                    enabled = false
                }
            } catch (e: Exception) {
                Log.w(TAG, "Virtualizer not supported", e)
            }
            
            loadSettings()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing spatial audio system", e)
        }
    }
    
    fun release() {
        try {
            virtualizer?.release()
            virtualizer = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing spatial audio system", e)
        }
    }
    
    // Main spatial audio control
    fun setSpatialEnabled(enabled: Boolean) {
        _spatialEnabled.value = enabled
        prefs.edit().putBoolean(PREF_SPATIAL_ENABLED, enabled).apply()
        updateSpatialProcessing()
    }
    
    // Binaural rendering
    fun setBinauralEnabled(enabled: Boolean) {
        _binauralEnabled.value = enabled
        prefs.edit().putBoolean(PREF_BINAURAL_ENABLED, enabled).apply()
        updateSpatialProcessing()
    }
    
    // Cross-feed controls
    fun setCrossfeedEnabled(enabled: Boolean) {
        _crossfeedEnabled.value = enabled
        prefs.edit().putBoolean(PREF_CROSSFEED_ENABLED, enabled).apply()
        updateSpatialProcessing()
    }
    
    fun setCrossfeedStrength(strength: Float) {
        _crossfeedStrength.value = strength.coerceIn(0.0f, 1.0f)
        prefs.edit().putFloat(PREF_CROSSFEED_STRENGTH, _crossfeedStrength.value).apply()
        updateSpatialProcessing()
    }
    
    // Room simulation
    fun setRoomSize(size: Float) {
        _roomSize.value = size.coerceIn(0.0f, 1.0f)
        prefs.edit().putFloat(PREF_ROOM_SIZE, _roomSize.value).apply()
        updateSpatialProcessing()
    }
    
    fun setRoomReflections(reflections: Float) {
        _roomReflections.value = reflections.coerceIn(0.0f, 1.0f)
        prefs.edit().putFloat(PREF_ROOM_REFLECTIONS, _roomReflections.value).apply()
        updateSpatialProcessing()
    }
    
    // Virtual surround
    fun setSurroundEnabled(enabled: Boolean) {
        _surroundEnabled.value = enabled
        prefs.edit().putBoolean(PREF_SURROUND_ENABLED, enabled).apply()
        updateVirtualSurround()
    }
    
    fun setSurroundAngle(angle: Float) {
        _surroundAngle.value = angle.coerceIn(30.0f, 180.0f)
        prefs.edit().putFloat(PREF_SURROUND_ANGLE, _surroundAngle.value).apply()
        updateVirtualSurround()
    }
    
    // HRTF personalization
    fun setHeadSize(size: Float) {
        _headSize.value = size.coerceIn(0.5f, 1.5f)
        prefs.edit().putFloat(PREF_HEAD_SIZE, _headSize.value).apply()
        updateSpatialProcessing()
    }
    
    // Distance modeling
    fun setDistanceAttenuation(attenuation: Float) {
        _distanceAttenuation.value = attenuation.coerceIn(0.0f, 1.0f)
        prefs.edit().putFloat(PREF_DISTANCE_ATTENUATION, _distanceAttenuation.value).apply()
        updateSpatialProcessing()
    }
    
    // Elevation processing
    fun setElevationEnabled(enabled: Boolean) {
        _elevationEnabled.value = enabled
        prefs.edit().putBoolean(PREF_ELEVATION_ENABLED, enabled).apply()
        updateSpatialProcessing()
    }
    
    // Audio source positioning
    fun setAudioPosition(azimuth: Float, elevation: Float, distance: Float) {
        _azimuth.value = azimuth
        _elevation.value = elevation.coerceIn(-90.0f, 90.0f)
        _distance.value = distance.coerceIn(0.1f, 10.0f)
        updateSpatialProcessing()
    }
    
    private fun updateSpatialProcessing() {
        if (!_spatialEnabled.value) return
        
        try {
            // Apply all spatial processing effects
            applyCrossfeed()
            applyBinauralProcessing()
            applyRoomSimulation()
            applyDistanceAttenuation()
            applyElevationProcessing()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error updating spatial processing", e)
        }
    }
    
    private fun updateVirtualSurround() {
        try {
            virtualizer?.let { virt ->
                if (_surroundEnabled.value && _spatialEnabled.value) {
                    val strength = ((_surroundAngle.value - 30.0f) / 150.0f * 1000).toInt().toShort()
                    virt.setStrength(strength)
                    virt.enabled = true
                } else {
                    virt.enabled = false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating virtual surround", e)
        }
    }
    
    private fun applyCrossfeed() {
        if (!_crossfeedEnabled.value) return
        
        // Crossfeed implementation for reducing stereo fatigue
        // This would typically involve mixing a portion of left channel to right and vice versa
        val crossfeedAmount = _crossfeedStrength.value
        Log.d(TAG, "Applying crossfeed with strength: $crossfeedAmount")
        
        // In a real implementation, this would process audio buffers:
        // leftOutput = leftInput + (rightInput * crossfeedAmount)
        // rightOutput = rightInput + (leftInput * crossfeedAmount)
    }
    
    private fun applyBinauralProcessing() {
        if (!_binauralEnabled.value) return
        
        // HRTF-based binaural rendering
        val azimuthRad = Math.toRadians(_azimuth.value.toDouble())
        val elevationRad = Math.toRadians(_elevation.value.toDouble())
        val headRadius = DEFAULT_HEAD_RADIUS * _headSize.value
        
        // Calculate inter-aural time difference (ITD)
        val itd = calculateITD(azimuthRad, headRadius)
        
        // Calculate inter-aural level difference (ILD)
        val ild = calculateILD(azimuthRad, elevationRad)
        
        // Apply spectral filtering for elevation cues
        val spectralShaping = calculateSpectralShaping(elevationRad)
        
        Log.d(TAG, "Binaural processing - ITD: ${itd}ms, ILD: ${ild}dB, Spectral: $spectralShaping")
        
        // In a real implementation, these values would be used to:
        // 1. Delay one channel by ITD
        // 2. Attenuate channels based on ILD
        // 3. Apply spectral filtering for elevation
    }
    
    private fun calculateITD(azimuthRad: Double, headRadius: Float): Float {
        // Woodworth formula for ITD calculation
        val itdSeconds = (headRadius / SOUND_SPEED) * (azimuthRad + sin(azimuthRad))
        return (itdSeconds * 1000).toFloat() // Convert to milliseconds
    }
    
    private fun calculateILD(azimuthRad: Double, elevationRad: Double): Float {
        // Simplified ILD calculation based on head shadowing
        val lateralGain = cos(azimuthRad).toFloat()
        val elevationGain = cos(elevationRad).toFloat()
        return lateralGain * elevationGain * 20.0f // Max 20dB difference
    }
    
    private fun calculateSpectralShaping(elevationRad: Double): Float {
        // Simplified spectral shaping for elevation cues
        // Higher elevations typically boost high frequencies
        return sin(elevationRad).toFloat() * 6.0f // Max 6dB boost/cut
    }
    
    private fun applyRoomSimulation() {
        if (_roomSize.value == 0.0f && _roomReflections.value == 0.0f) return
        
        // Room acoustics simulation
        val roomVolume = _roomSize.value * 100 // Scale to reasonable room size
        val reflectionStrength = _roomReflections.value
        val rt60 = roomVolume * 0.5f // Simplified RT60 calculation
        
        Log.d(TAG, "Room simulation - Size: $roomVolume, Reflections: $reflectionStrength, RT60: ${rt60}s")
        
        // In a real implementation, this would:
        // 1. Generate early reflections based on room geometry
        // 2. Add reverb tail with appropriate decay time
        // 3. Apply frequency-dependent absorption
    }
    
    private fun applyDistanceAttenuation() {
        if (_distance.value == 1.0f) return
        
        // Distance-based attenuation and filtering
        val attenuationDb = 20 * log10(_distance.value) * _distanceAttenuation.value
        val highFreqRolloff = (_distance.value - 1.0f) * 0.5f // Air absorption simulation
        
        Log.d(TAG, "Distance processing - Attenuation: ${attenuationDb}dB, HF rolloff: $highFreqRolloff")
        
        // In a real implementation, this would:
        // 1. Apply level attenuation based on inverse square law
        // 2. Apply high-frequency rolloff for air absorption
        // 3. Add slight reverb increase for distant sources
    }
    
    private fun applyElevationProcessing() {
        if (!_elevationEnabled.value) return
        
        val elevationRad = Math.toRadians(_elevation.value.toDouble())
        
        // Elevation affects spectral content (pinna filtering)
        val spectralTilt = sin(elevationRad).toFloat() * 3.0f // dB/octave tilt
        val notchFrequency = 8000 + (elevationRad * 2000).toFloat() // Elevation-dependent notch
        
        Log.d(TAG, "Elevation processing - Tilt: ${spectralTilt}dB/oct, Notch: ${notchFrequency}Hz")
        
        // In a real implementation, this would:
        // 1. Apply spectral tilt based on elevation angle
        // 2. Create elevation-dependent notch filter
        // 3. Modify early reflection patterns
    }
    
    // Preset management for different listening scenarios
    fun applySpatialPreset(preset: SpatialAudioPreset) {
        when (preset) {
            SpatialAudioPreset.HEADPHONES_OPTIMAL -> {
                setSpatialEnabled(true)
                setBinauralEnabled(true)
                setCrossfeedEnabled(true)
                setCrossfeedStrength(0.3f)
                setSurroundEnabled(false)
                setRoomSize(0.2f)
                setRoomReflections(0.1f)
                setElevationEnabled(true)
            }
            SpatialAudioPreset.SPEAKERS_NEARFIELD -> {
                setSpatialEnabled(true)
                setBinauralEnabled(false)
                setCrossfeedEnabled(false)
                setSurroundEnabled(true)
                setSurroundAngle(60.0f)
                setRoomSize(0.3f)
                setRoomReflections(0.2f)
                setElevationEnabled(false)
            }
            SpatialAudioPreset.IMMERSIVE_SURROUND -> {
                setSpatialEnabled(true)
                setBinauralEnabled(true)
                setCrossfeedEnabled(false)
                setSurroundEnabled(true)
                setSurroundAngle(120.0f)
                setRoomSize(0.8f)
                setRoomReflections(0.6f)
                setElevationEnabled(true)
            }
            SpatialAudioPreset.INTIMATE_STUDIO -> {
                setSpatialEnabled(true)
                setBinauralEnabled(true)
                setCrossfeedEnabled(true)
                setCrossfeedStrength(0.2f)
                setSurroundEnabled(false)
                setRoomSize(0.1f)
                setRoomReflections(0.05f)
                setElevationEnabled(false)
            }
            SpatialAudioPreset.CONCERT_HALL -> {
                setSpatialEnabled(true)
                setBinauralEnabled(true)
                setCrossfeedEnabled(false)
                setSurroundEnabled(true)
                setSurroundAngle(140.0f)
                setRoomSize(1.0f)
                setRoomReflections(0.8f)
                setElevationEnabled(true)
            }
        }
    }
    
    // Audio analysis for automatic spatial optimization
    fun analyzeStereoContent(leftChannel: FloatArray, rightChannel: FloatArray): StereoAnalysis {
        try {
            // Calculate stereo width
            val correlation = calculateStereoCorrelation(leftChannel, rightChannel)
            val width = 1.0f - abs(correlation)
            
            // Calculate balance
            val leftRms = sqrt(leftChannel.map { it * it }.average()).toFloat()
            val rightRms = sqrt(rightChannel.map { it * it }.average()).toFloat()
            val balance = (rightRms - leftRms) / (rightRms + leftRms + 1e-10f)
            
            // Detect if content is mono
            val isMono = correlation > 0.95f
            
            // Estimate source positions (simplified)
            val estimatedAzimuth = balance * 45.0f // Rough azimuth estimation
            
            return StereoAnalysis(
                stereoWidth = width,
                balance = balance,
                isMono = isMono,
                estimatedAzimuth = estimatedAzimuth,
                correlation = correlation
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing stereo content", e)
            return StereoAnalysis()
        }
    }
    
    private fun calculateStereoCorrelation(left: FloatArray, right: FloatArray): Float {
        if (left.size != right.size) return 0.0f
        
        val leftMean = left.average().toFloat()
        val rightMean = right.average().toFloat()
        
        var numerator = 0.0f
        var leftSumSq = 0.0f
        var rightSumSq = 0.0f
        
        for (i in left.indices) {
            val leftDiff = left[i] - leftMean
            val rightDiff = right[i] - rightMean
            numerator += leftDiff * rightDiff
            leftSumSq += leftDiff * leftDiff
            rightSumSq += rightDiff * rightDiff
        }
        
        val denominator = sqrt(leftSumSq * rightSumSq)
        return if (denominator > 0) numerator / denominator else 0.0f
    }
    
    private fun loadSettings() {
        _spatialEnabled.value = prefs.getBoolean(PREF_SPATIAL_ENABLED, false)
        _binauralEnabled.value = prefs.getBoolean(PREF_BINAURAL_ENABLED, false)
        _crossfeedEnabled.value = prefs.getBoolean(PREF_CROSSFEED_ENABLED, false)
        _crossfeedStrength.value = prefs.getFloat(PREF_CROSSFEED_STRENGTH, 0.3f)
        _roomSize.value = prefs.getFloat(PREF_ROOM_SIZE, 0.5f)
        _roomReflections.value = prefs.getFloat(PREF_ROOM_REFLECTIONS, 0.3f)
        _surroundEnabled.value = prefs.getBoolean(PREF_SURROUND_ENABLED, false)
        _surroundAngle.value = prefs.getFloat(PREF_SURROUND_ANGLE, 90.0f)
        _headSize.value = prefs.getFloat(PREF_HEAD_SIZE, 1.0f)
        _distanceAttenuation.value = prefs.getFloat(PREF_DISTANCE_ATTENUATION, 0.5f)
        _elevationEnabled.value = prefs.getBoolean(PREF_ELEVATION_ENABLED, false)
        
        // Apply loaded settings
        updateSpatialProcessing()
        updateVirtualSurround()
    }
}

enum class SpatialAudioPreset {
    HEADPHONES_OPTIMAL,
    SPEAKERS_NEARFIELD,
    IMMERSIVE_SURROUND,
    INTIMATE_STUDIO,
    CONCERT_HALL
}

data class StereoAnalysis(
    val stereoWidth: Float = 0.5f,
    val balance: Float = 0.0f,
    val isMono: Boolean = false,
    val estimatedAzimuth: Float = 0.0f,
    val correlation: Float = 0.0f
)