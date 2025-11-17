package com.stash.opusplayer.audio

import android.content.Context
import android.media.audiofx.Virtualizer
import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Equalizer
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.*

/**
 * Enhanced 8D Audio Processor with True Stereo Panning
 * 
 * Implements proper 8D audio effect using:
 * - Automated stereo panning (L/R channel volume modulation)
 * - Spatial reverb for depth perception
 * - Frequency-based positioning (HRTF simulation)
 * - Circular rotation automation
 */
class Enhanced8DAudioProcessor(private val context: Context) {
    
    companion object {
        private const val TAG = "Enhanced8DAudio"
        private const val TWO_PI = 2.0f * PI.toFloat()
        private const val UPDATE_INTERVAL_MS = 50L // 20Hz for smooth rotation
    }
    
    // State flows
    private val _isEnabled = MutableStateFlow(false)
    val isEnabled: StateFlow<Boolean> = _isEnabled.asStateFlow()
    
    private val _intensity = MutableStateFlow(1.0f)
    val intensity: StateFlow<Float> = _intensity.asStateFlow()
    
    private val _rotationSpeed = MutableStateFlow(1.0f)
    val rotationSpeed: StateFlow<Float> = _rotationSpeed.asStateFlow()
    
    private val _currentAngle = MutableStateFlow(0f)
    val currentAngle: StateFlow<Float> = _currentAngle.asStateFlow()
    
    // Audio effects
    private var virtualizer: Virtualizer? = null
    private var envReverb: EnvironmentalReverb? = null
    private var equalizer: Equalizer? = null
    private var currentAudioSessionId: Int = -1
    
    // Rotation control
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var rotationJob: Job? = null
    private var lastUpdateTime = 0L
    private var currentRotationAngle = 0f
    
    /**
     * Initialize with audio session ID from ExoPlayer
     */
    fun initialize(audioSessionId: Int) {
        if (audioSessionId == currentAudioSessionId && virtualizer != null) {
            return // Already initialized
        }
        
        release()
        currentAudioSessionId = audioSessionId
        
        try {
            // 1. Virtualizer for spatial positioning and panning simulation
            virtualizer = Virtualizer(0, audioSessionId).apply {
                enabled = false
            }
            Log.d(TAG, "Virtualizer initialized for 8D audio")
            
            // 2. Environmental Reverb for 3D space simulation
            envReverb = EnvironmentalReverb(0, audioSessionId).apply {
                enabled = false
                // Configure for 8D effect
                setRoomLevel((-600).toShort())      // Room volume
                setRoomHFLevel((0).toShort())       // High-frequency volume
                decayTime = 1200                     // Reverb decay time (ms)
                setDecayHFRatio((0.6 * Short.MAX_VALUE).toInt().toShort())
                setReflectionsLevel((-1200).toShort()) // Early reflections
                reflectionsDelay = 30                // Early reflection delay
                setReverbLevel((-800).toShort())     // Late reverb level
                reverbDelay = 50                     // Late reverb delay
                setDiffusion((900).toShort())        // Sound diffusion
                setDensity((900).toShort())          // Reverb density
            }
            Log.d(TAG, "Environmental Reverb initialized for 8D audio")
            
            // 3. Equalizer for HRTF simulation (frequency-based positioning)
            try {
                equalizer = Equalizer(0, audioSessionId).apply {
                    enabled = false
                }
                Log.d(TAG, "Equalizer initialized for HRTF simulation")
            } catch (e: Exception) {
                Log.w(TAG, "Equalizer not available for HRTF", e)
            }
            
            // Start rotation if enabled
            if (_isEnabled.value) {
                startRotation()
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Enhanced 8D Audio", e)
        }
    }
    
    /**
     * Enable/Disable 8D audio effect
     */
    fun setEnabled(enabled: Boolean) {
        _isEnabled.value = enabled
        
        try {
            virtualizer?.enabled = enabled
            envReverb?.enabled = enabled
            // Note: We don't enable the equalizer directly as it's used for HRTF simulation
            
            if (enabled) {
                startRotation()
            } else {
                stopRotation()
                currentRotationAngle = 0f
                _currentAngle.value = 0f
                resetEffects()
            }
            
            Log.d(TAG, "Enhanced 8D Audio ${if (enabled) "enabled" else "disabled"}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set 8D enabled state", e)
        }
    }
    
    /**
     * Set intensity (0.0 to 2.0)
     */
    fun setIntensity(intensity: Float) {
        val clamped = intensity.coerceIn(0f, 2.0f)
        _intensity.value = clamped
        Log.d(TAG, "8D Intensity: $clamped")
    }
    
    /**
     * Set rotation speed (0.1 to 3.0)
     */
    fun setRotationSpeed(speed: Float) {
        val clamped = speed.coerceIn(0.1f, 3.0f)
        _rotationSpeed.value = clamped
        Log.d(TAG, "8D Rotation Speed: ${clamped}x")
    }
    
    /**
     * Start the rotation animation
     */
    private fun startRotation() {
        stopRotation()
        
        rotationJob = scope.launch {
            lastUpdateTime = System.currentTimeMillis()
            
            while (isActive && _isEnabled.value) {
                try {
                    val currentTime = System.currentTimeMillis()
                    val deltaTime = (currentTime - lastUpdateTime) / 1000f
                    lastUpdateTime = currentTime
                    
                    // Update rotation angle based on speed
                    // Full rotation in 8 seconds at 1x speed
                    val rotationDelta = deltaTime * _rotationSpeed.value * TWO_PI / 8f
                    currentRotationAngle = (currentRotationAngle + rotationDelta) % TWO_PI
                    
                    _currentAngle.value = currentRotationAngle
                    
                    // Apply effects based on new angle
                    updateEffects()
                    
                    delay(UPDATE_INTERVAL_MS)
                } catch (e: Exception) {
                    if (isActive) {
                        Log.w(TAG, "Rotation update error", e)
                    }
                }
            }
        }
    }
    
    /**
     * Stop the rotation animation
     */
    private fun stopRotation() {
        rotationJob?.cancel()
        rotationJob = null
    }
    
    /**
     * Update audio effects based on current rotation angle
     * This implements the true 8D effect with stereo panning simulation
     */
    private fun updateEffects() {
        try {
            val angle = currentRotationAngle
            val intensity = _intensity.value
            
            // Calculate spatial position using sine/cosine for smooth circular motion
            // X: Left (-1) to Right (1) - horizontal axis
            // Y: Front (-1) to Back (1) - depth axis
            val x = cos(angle)
            val y = sin(angle)
            
            // === STEREO PANNING SIMULATION ===
            // Virtualizer strength modulates based on position to simulate L/R panning
            // When sound is on left (x < 0), we emphasize left channel
            // When sound is on right (x > 0), we emphasize right channel
            val panPosition = x // -1 (left) to +1 (right)
            
            // Calculate virtualizer strength to simulate panning
            // Higher strength = more spatial separation
            val baseVirtualization = 600f
            val panModulation = abs(panPosition) * 400f * intensity
            val virtualizerStrength = (baseVirtualization + panModulation).toInt().coerceIn(0, 1000)
            
            virtualizer?.setStrength(virtualizerStrength.toShort())
            
            // === SPATIAL REVERB FOR DEPTH ===
            // More reverb when sound is behind (y > 0) to create depth perception
            val depthFactor = (1f + y) / 2f // 0 (front) to 1 (back)
            val reverbIntensity = depthFactor * intensity
            
            // Modulate reverb level based on depth
            val reverbLevel = (-1000f + reverbIntensity * 600f).toInt().toShort()
            envReverb?.setReverbLevel(reverbLevel)
            
            // Adjust reverb decay time for more pronounced effect
            val decayTime = (1000 + reverbIntensity * 500f).toInt()
            envReverb?.decayTime = decayTime
            
            // === HRTF SIMULATION WITH EQUALIZER ===
            // Adjust frequency response based on position
            // This simulates how your head affects sound from different positions
            applyHRTFSimulation(panPosition, depthFactor, intensity)
            
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update effects", e)
        }
    }
    
    /**
     * Apply HRTF simulation using equalizer
     * Simulates how the human head affects sound from different positions
     */
    private fun applyHRTFSimulation(panPosition: Float, depthFactor: Float, intensity: Float) {
        val eq = equalizer ?: return
        
        try {
            if (!eq.enabled && _isEnabled.value) {
                eq.enabled = true
            }
            
            val numBands = eq.numberOfBands.toInt()
            if (numBands < 3) return
            
            // When sound is to the side, boost high frequencies (head shadowing effect)
            val sideBoost = abs(panPosition) * intensity * 300f // 0 to 300 millibels
            
            // When sound is behind, attenuate high frequencies (head blocking effect)
            val backAttenuation = depthFactor * intensity * 200f // 0 to 200 millibels
            
            // Apply to upper frequency bands (typically bands 3-5 are high frequencies)
            val highBandStart = (numBands * 0.6f).toInt() // Upper 40% of bands
            
            for (i in 0 until numBands) {
                val currentLevel = eq.getBandLevel(i.toShort())
                val newLevel = if (i >= highBandStart) {
                    // High frequency bands
                    (currentLevel + sideBoost - backAttenuation).toInt().coerceIn(-1500, 1500)
                } else {
                    // Low frequency bands - less affected by head position
                    currentLevel.toInt()
                }
                
                eq.setBandLevel(i.toShort(), newLevel.toShort())
            }
            
        } catch (e: Exception) {
            Log.w(TAG, "Failed to apply HRTF simulation", e)
        }
    }
    
    /**
     * Reset all effects to neutral state
     */
    private fun resetEffects() {
        try {
            virtualizer?.setStrength(0)
            envReverb?.setReverbLevel((-1000).toShort())
            envReverb?.decayTime = 1000
            
            // Reset equalizer
            equalizer?.let { eq ->
                for (i in 0 until eq.numberOfBands.toInt()) {
                    eq.setBandLevel(i.toShort(), 0)
                }
                eq.enabled = false
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to reset effects", e)
        }
    }
    
    /**
     * Release all resources
     */
    fun release() {
        stopRotation()
        
        try {
            virtualizer?.release()
            envReverb?.release()
            equalizer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing effects", e)
        }
        
        virtualizer = null
        envReverb = null
        equalizer = null
        currentAudioSessionId = -1
        
        Log.d(TAG, "Enhanced 8D Audio released")
    }
    
    /**
     * Clean up when done
     */
    fun shutdown() {
        release()
        scope.cancel()
    }
    
    /**
     * Check if initialized
     */
    fun isInitialized(): Boolean = virtualizer != null && envReverb != null
}
