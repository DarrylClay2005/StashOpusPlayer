package com.stash.opusplayer.audio

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.preference.PreferenceManager
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * Enhanced Audio Manager
 * 
 * Integrates and coordinates all advanced audio processing systems:
 * - Advanced Audio Effects Engine
 * - Spatial Audio System  
 * - Intelligent Auto-EQ
 * - Audio Analysis Engine
 * - Existing EqualizerManager integration
 * 
 * Provides a unified interface for all audio enhancement features.
 */
class EnhancedAudioManager(private val context: Context) {
    
    companion object {
        private const val TAG = "EnhancedAudioManager"
        
        // Global preferences
        private const val PREF_ENHANCED_AUDIO_ENABLED = "enhanced_audio_enabled"
        private const val PREF_CURRENT_PROFILE = "current_audio_profile"
        private const val PREF_AUTO_PROFILE_SWITCHING = "auto_profile_switching"
        private const val PREF_CROSS_SYSTEM_SYNC = "cross_system_sync_enabled"
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    
    // Advanced audio systems
    private val advancedEffects = AdvancedAudioEffects(context)
    private val spatialAudio = SpatialAudioSystem(context)
    private val intelligentEQ = IntelligentAutoEQ(context)
    private val audioAnalysis = AudioAnalysisEngine(context)
    
    // Integration with existing EqualizerManager
    private var equalizerManager: EqualizerManager? = null
    
    // State management
    private val _enhancedAudioEnabled = MutableStateFlow(false)
    val enhancedAudioEnabled: StateFlow<Boolean> = _enhancedAudioEnabled.asStateFlow()
    
    private val _currentProfile = MutableStateFlow(AudioProfile.BALANCED)
    val currentProfile: StateFlow<AudioProfile> = _currentProfile.asStateFlow()
    
    private val _autoProfileSwitching = MutableStateFlow(false)
    val autoProfileSwitching: StateFlow<Boolean> = _autoProfileSwitching.asStateFlow()
    
    private val _crossSystemSync = MutableStateFlow(true)
    val crossSystemSync: StateFlow<Boolean> = _crossSystemSync.asStateFlow()
    
    // Combined audio state
    private val _overallAudioQuality = MutableStateFlow(OverallAudioState())
    val overallAudioQuality: StateFlow<OverallAudioState> = _overallAudioQuality.asStateFlow()
    
    // System status
    private val _systemStatus = MutableStateFlow(SystemStatus())
    val systemStatus: StateFlow<SystemStatus> = _systemStatus.asStateFlow()
    
    private var currentAudioSessionId = 0
    private var isInitialized = false
    
    fun initialize(audioSessionId: Int, existingEqualizerManager: EqualizerManager? = null) {
        try {
            currentAudioSessionId = audioSessionId
            equalizerManager = existingEqualizerManager
            
            // Initialize all subsystems
            advancedEffects.initialize(audioSessionId)
            spatialAudio.initialize(audioSessionId)
            intelligentEQ.initialize(audioSessionId)
            audioAnalysis.initialize(audioSessionId)
            
            // Load settings
            loadSettings()
            
            // Set up cross-system synchronization
            if (_crossSystemSync.value) {
                setupCrossSystemSync()
            }
            
            // Start monitoring systems
            startSystemMonitoring()
            
            isInitialized = true
            
            Log.i(TAG, "Enhanced Audio Manager initialized successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing Enhanced Audio Manager", e)
        }
    }
    
    fun release() {
        try {
            scope.cancel()
            
            advancedEffects.release()
            spatialAudio.release()
            intelligentEQ.release()
            audioAnalysis.release()
            
            isInitialized = false
            
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing Enhanced Audio Manager", e)
        }
    }
    
    // Main control functions
    fun setEnhancedAudioEnabled(enabled: Boolean) {
        _enhancedAudioEnabled.value = enabled
        prefs.edit().putBoolean(PREF_ENHANCED_AUDIO_ENABLED, enabled).apply()
        
        if (enabled) {
            applyCurrentProfile()
        } else {
            disableAllSystems()
        }
        
        updateSystemStatus()
    }
    
    fun setAudioProfile(profile: AudioProfile) {
        _currentProfile.value = profile
        prefs.edit().putString(PREF_CURRENT_PROFILE, profile.name).apply()
        
        if (_enhancedAudioEnabled.value) {
            applyProfile(profile)
        }
        
        updateSystemStatus()
    }
    
    fun setAutoProfileSwitching(enabled: Boolean) {
        _autoProfileSwitching.value = enabled
        prefs.edit().putBoolean(PREF_AUTO_PROFILE_SWITCHING, enabled).apply()
        
        if (enabled) {
            startAutoProfileSwitching()
        } else {
            stopAutoProfileSwitching()
        }
    }
    
    fun setCrossSystemSync(enabled: Boolean) {
        _crossSystemSync.value = enabled
        prefs.edit().putBoolean(PREF_CROSS_SYSTEM_SYNC, enabled).apply()
        
        if (enabled) {
            setupCrossSystemSync()
        }
    }
    
    // Audio content analysis integration
    fun analyzeCurrentTrack(samples: FloatArray, metadata: TrackMetadata? = null) {
        if (!_enhancedAudioEnabled.value) return
        
        scope.launch(Dispatchers.Default) {
            try {
                // Run analysis on all systems
                // AudioAnalysisEngine doesn't have analyzeAudioContent method, skip for now
                intelligentEQ.analyzeAudioContent(samples, metadata?.genre)
                // Advanced effects don't need direct audio samples
                
                // Auto-adjust profile if enabled
                if (_autoProfileSwitching.value) {
                    val recommendedProfile = determineOptimalProfile(metadata)
                    if (recommendedProfile != _currentProfile.value) {
                        withContext(Dispatchers.Main) {
                            setAudioProfile(recommendedProfile)
                        }
                    }
                }
                
                // Update overall audio state
                updateOverallAudioState()
                
            } catch (e: Exception) {
                Log.e(TAG, "Error analyzing audio content", e)
            }
        }
    }
    
    fun analyzeStereoContent(leftChannel: FloatArray, rightChannel: FloatArray) {
        if (!_enhancedAudioEnabled.value) return
        
        scope.launch(Dispatchers.Default) {
            try {
                audioAnalysis.analyzeStereoContent(leftChannel, rightChannel)
                
                val stereoAnalysis = spatialAudio.analyzeStereoContent(leftChannel, rightChannel)
                
                // Auto-adjust spatial settings based on content
                if (_crossSystemSync.value) {
                    adjustSpatialSettingsBasedOnContent(stereoAnalysis)
                }
                
                updateOverallAudioState()
                
            } catch (e: Exception) {
                Log.e(TAG, "Error analyzing stereo content", e)
            }
        }
    }
    
    // Profile management
    private fun applyCurrentProfile() {
        if (!isInitialized) return
        applyProfile(_currentProfile.value)
    }
    
    private fun applyProfile(profile: AudioProfile) {
        scope.launch(Dispatchers.Default) {
            try {
                when (profile) {
                    AudioProfile.AUDIOPHILE -> applyAudiophileProfile()
                    AudioProfile.BASS_BOOST -> applyBassBoostProfile()
                    AudioProfile.VOCAL_CLARITY -> applyVocalClarityProfile()
                    AudioProfile.GAMING -> applyGamingProfile()
                    AudioProfile.CLASSICAL -> applyClassicalProfile()
                    AudioProfile.ELECTRONIC -> applyElectronicProfile()
                    AudioProfile.ROCK_METAL -> applyRockMetalProfile()
                    AudioProfile.JAZZ_ACOUSTIC -> applyJazzAcousticProfile()
                    AudioProfile.BALANCED -> applyBalancedProfile()
                    AudioProfile.CUSTOM -> applyCustomProfile()
                }
                
                Log.d(TAG, "Applied audio profile: $profile")
                
            } catch (e: Exception) {
                Log.e(TAG, "Error applying audio profile: $profile", e)
            }
        }
    }
    
    private fun applyAudiophileProfile() {
        // Ultra-clean, transparent sound
        advancedEffects.applyEnhancementPreset(AudioEnhancementPreset.AUDIOPHILE)
        spatialAudio.applySpatialPreset(SpatialAudioPreset.HEADPHONES_OPTIMAL)
        intelligentEQ.setAutoEQEnabled(false)
        intelligentEQ.setReferenceCurve(ReferenceCurve.HARMAN_TARGET)
        audioAnalysis.setAnalysisEnabled(true)
        
        // Integrate with existing equalizer
        equalizerManager?.let { eq ->
            eq.setEnabled(false)
            // Apply flat/reference curve
        }
    }
    
    private fun applyBassBoostProfile() {
        // Enhanced low-end with controlled dynamics
        advancedEffects.setCompressorEnabled(true)
        advancedEffects.setCompressorThreshold(-10.0f)
        advancedEffects.setLimiterEnabled(true)
        advancedEffects.setExciterEnabled(true)
        
        spatialAudio.setSpatialEnabled(false) // Focus on direct bass impact
        
        intelligentEQ.setAutoEQEnabled(true)
        intelligentEQ.setGenreOptimizationEnabled(false) // Manual bass focus
        
        equalizerManager?.let { eq ->
            eq.setBassBoost(800) // Strong bass boost
            eq.setEnabled(true)
        }
    }
    
    private fun applyVocalClarityProfile() {
        // Optimized for speech and vocals
        advancedEffects.setCompressorEnabled(true)
        advancedEffects.setCompressorRatio(3.0f)
        advancedEffects.setExciterEnabled(true)
        advancedEffects.setExciterHarmonics(0.4f)
        
        spatialAudio.setCrossfeedEnabled(true)
        spatialAudio.setCrossfeedStrength(0.2f)
        spatialAudio.setSurroundEnabled(false)
        
        intelligentEQ.setAutoEQEnabled(true)
        intelligentEQ.setReferenceCurve(ReferenceCurve.DIFFUSE_FIELD)
        
        audioAnalysis.setAnalysisEnabled(true)
        audioAnalysis.setPeakDetectionEnabled(true)
    }
    
    private fun applyGamingProfile() {
        // Enhanced spatial awareness and dynamics
        advancedEffects.setLimiterEnabled(true)
        advancedEffects.setLimiterThreshold(-1.0f)
        // Enable spatial surround for gaming
        spatialAudio.setSurroundEnabled(true)
        spatialAudio.setSurroundAngle(120.0f)
        
        spatialAudio.applySpatialPreset(SpatialAudioPreset.IMMERSIVE_SURROUND)
        spatialAudio.setElevationEnabled(true)
        
        intelligentEQ.setAutoEQEnabled(true)
        intelligentEQ.setDynamicAdjustmentEnabled(true)
        
        equalizerManager?.let { eq ->
            eq.setVirtualizer(800)
            eq.setEnabled(true)
        }
    }
    
    private fun applyClassicalProfile() {
        // Natural, spacious sound with wide dynamic range
        advancedEffects.setCompressorEnabled(false)
        advancedEffects.setLimiterEnabled(false)
        advancedEffects.setTubeWarmthEnabled(true)
        advancedEffects.setTubeDrive(0.2f)
        
        spatialAudio.applySpatialPreset(SpatialAudioPreset.CONCERT_HALL)
        
        intelligentEQ.setAutoEQEnabled(true)
        intelligentEQ.setReferenceCurve(ReferenceCurve.FLAT)
        intelligentEQ.setLoudnessCompensation(0.3f)
        
        audioAnalysis.setAnalysisEnabled(true)
    }
    
    private fun applyElectronicProfile() {
        // Punchy, wide stereo with controlled peaks
        advancedEffects.applyEnhancementPreset(AudioEnhancementPreset.LOUD_AND_PUNCHY)
        
        spatialAudio.setSurroundEnabled(true)
        spatialAudio.setSurroundAngle(140.0f)
        spatialAudio.setSurroundEnabled(true)
        
        intelligentEQ.setAutoEQEnabled(true)
        intelligentEQ.setGenreOptimizationEnabled(true)
        
        equalizerManager?.let { eq ->
            eq.setBassBoost(600)
            eq.setVirtualizer(500)
        }
    }
    
    private fun applyRockMetalProfile() {
        // Aggressive, forward sound with harmonic enhancement
        advancedEffects.setCompressorEnabled(true)
        advancedEffects.setCompressorRatio(5.0f)
        advancedEffects.setExciterEnabled(true)
        advancedEffects.setExciterHarmonics(0.5f)
        
        spatialAudio.setSpatialEnabled(false) // Direct, in-your-face sound
        
        intelligentEQ.setAutoEQEnabled(true)
        intelligentEQ.setFrequencySensitivity(0.8f)
        
        equalizerManager?.let { eq ->
            eq.setBassBoost(500)
            eq.setEnabled(true)
        }
    }
    
    private fun applyJazzAcousticProfile() {
        // Warm, intimate sound with natural dynamics
        advancedEffects.applyEnhancementPreset(AudioEnhancementPreset.WARM_VINTAGE)
        
        spatialAudio.applySpatialPreset(SpatialAudioPreset.INTIMATE_STUDIO)
        
        intelligentEQ.setAutoEQEnabled(true)
        intelligentEQ.setLoudnessCompensation(0.4f)
        
        audioAnalysis.setAnalysisEnabled(true)
    }
    
    private fun applyBalancedProfile() {
        // Neutral, versatile settings
        advancedEffects.applyEnhancementPreset(AudioEnhancementPreset.TRANSPARENT)
        
        spatialAudio.applySpatialPreset(SpatialAudioPreset.HEADPHONES_OPTIMAL)
        
        intelligentEQ.setAutoEQEnabled(true)
        intelligentEQ.setReferenceCurve(ReferenceCurve.HARMAN_TARGET)
        intelligentEQ.setAdaptationSpeed(0.5f)
        
        audioAnalysis.setAnalysisEnabled(true)
    }
    
    private fun applyCustomProfile() {
        // Load user's custom settings (implementation would load from preferences)
        Log.d(TAG, "Loading custom audio profile settings")
    }
    
    private fun disableAllSystems() {
        advancedEffects.setCompressorEnabled(false)
        advancedEffects.setLimiterEnabled(false)
        advancedEffects.setExciterEnabled(false)
        advancedEffects.setTubeWarmthEnabled(false)
        
        spatialAudio.setSpatialEnabled(false)
        
        intelligentEQ.setAutoEQEnabled(false)
        
        audioAnalysis.setAnalysisEnabled(false)
    }
    
    // Auto profile switching based on content analysis
    private fun determineOptimalProfile(metadata: TrackMetadata?): AudioProfile {
        val genre = metadata?.genre?.lowercase() ?: "unknown"
        val tempo = intelligentEQ.detectedTempo.value
        val spectralBalance = intelligentEQ.spectralBalance.value
        
        return when {
            genre.contains("classical") || genre.contains("orchestral") -> AudioProfile.CLASSICAL
            genre.contains("electronic") || genre.contains("edm") || genre.contains("techno") -> AudioProfile.ELECTRONIC
            genre.contains("rock") || genre.contains("metal") -> AudioProfile.ROCK_METAL
            genre.contains("jazz") || genre.contains("acoustic") -> AudioProfile.JAZZ_ACOUSTIC
            genre.contains("vocal") || genre.contains("speech") -> AudioProfile.VOCAL_CLARITY
            spectralBalance.bassEnergy > 0.5f -> AudioProfile.BASS_BOOST
            tempo > 140 && spectralBalance.trebleEnergy > 0.4f -> AudioProfile.GAMING
            else -> AudioProfile.BALANCED
        }
    }
    
    private fun adjustSpatialSettingsBasedOnContent(@Suppress("UNUSED_PARAMETER") analysis: StereoAnalysis) {
        // Auto-adjust spatial settings based on stereo content
        // Auto-adjust spatial settings based on stereo content
        // This would adjust spatial processing parameters
    }
    
    // Cross-system synchronization
    private fun setupCrossSystemSync() {
        scope.launch {
            // Sync EQ changes with analysis feedback
            combine(
                intelligentEQ.currentGenre,
                audioAnalysis.spectralCentroid,
                audioAnalysis.audioQuality
            ) { genre, centroid, quality ->
                Triple(genre, centroid, quality)
            }.collect { (genre, centroid, quality) ->
                syncSystemsBasedOnAnalysis(genre, centroid, quality)
            }
        }
    }
    
    private fun syncSystemsBasedOnAnalysis(
        @Suppress("UNUSED_PARAMETER") genre: String,
        spectralCentroid: Float,
        audioQuality: AudioQuality
    ) {
        try {
            // Adjust compressor based on dynamic range
            if (audioQuality.dynamicRange < 6.0f) {
                advancedEffects.setCompressorEnabled(false) // Don't compress already compressed audio
            }
            
            // Adjust exciter based on spectral content
            if (spectralCentroid < 2000f) {
                advancedEffects.setExciterEnabled(true)
                advancedEffects.setExciterHarmonics(0.3f)
            }
            
            // Adjust spatial processing based on quality
            if (audioQuality.hasDistortion) {
                spatialAudio.setSpatialEnabled(false) // Don't spatialize distorted content
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing systems", e)
        }
    }
    
    // System monitoring
    private fun startSystemMonitoring() {
        scope.launch {
            while (isActive) {
                try {
                    updateSystemStatus()
                    updateOverallAudioState()
                    delay(1000) // Update every second
                } catch (e: Exception) {
                    Log.e(TAG, "Error in system monitoring", e)
                    delay(5000) // Wait longer on error
                }
            }
        }
    }
    
    private fun updateSystemStatus() {
        val status = SystemStatus(
            advancedEffectsActive = advancedEffects.compressorEnabled.value || 
                                   advancedEffects.limiterEnabled.value ||
                                   advancedEffects.exciterEnabled.value,
            spatialAudioActive = spatialAudio.spatialEnabled.value,
            intelligentEQActive = intelligentEQ.autoEQEnabled.value,
            audioAnalysisActive = audioAnalysis.analysisEnabled.value,
            overallCpuUsage = estimateCpuUsage(),
            memoryUsage = estimateMemoryUsage()
        )
        
        _systemStatus.value = status
    }
    
    private fun updateOverallAudioState() {
        scope.launch {
            try {
                val audioQuality = audioAnalysis.audioQuality.value
                val spatialState = spatialAudio.spatialEnabled.value
                val effectsState = advancedEffects.compressorEnabled.value
                val eqState = intelligentEQ.autoEQEnabled.value
                
                val overallState = OverallAudioState(
                    qualityRating = audioQuality.qualityRating,
                    dynamicRange = audioQuality.dynamicRange,
                    spatialProcessingActive = spatialState,
                    effectsProcessingActive = effectsState,
                    intelligentEQActive = eqState,
                    currentProfile = _currentProfile.value,
                    processingLatency = estimateProcessingLatency(),
                    recommendedProfile = if (_autoProfileSwitching.value) 
                        determineOptimalProfile(null) else null
                )
                
                _overallAudioQuality.value = overallState
                
            } catch (e: Exception) {
                Log.e(TAG, "Error updating overall audio state", e)
            }
        }
    }
    
    private fun estimateCpuUsage(): Float {
        // Simplified CPU usage estimation based on active systems
        var usage = 0.0f
        if (advancedEffects.compressorEnabled.value) usage += 5.0f
        if (spatialAudio.spatialEnabled.value) usage += 8.0f
        if (intelligentEQ.autoEQEnabled.value) usage += 12.0f
        if (audioAnalysis.analysisEnabled.value) usage += 15.0f
        return usage.coerceAtMost(100.0f)
    }
    
    private fun estimateMemoryUsage(): Float {
        // Simplified memory usage estimation
        var usage = 2.0f // Base usage
        if (audioAnalysis.analysisEnabled.value) usage += 8.0f
        if (intelligentEQ.learningEnabled.value) usage += 4.0f
        if (spatialAudio.spatialEnabled.value) usage += 3.0f
        return usage
    }
    
    private fun estimateProcessingLatency(): Float {
        // Simplified latency estimation in milliseconds
        var latency = 1.0f // Base latency
        if (advancedEffects.compressorEnabled.value) latency += 2.0f
        if (spatialAudio.spatialEnabled.value) latency += 5.0f
        if (intelligentEQ.autoEQEnabled.value) latency += 8.0f
        return latency
    }
    
    // Auto profile switching
    private fun startAutoProfileSwitching() {
        scope.launch {
            intelligentEQ.currentGenre.collect { genre ->
                if (_autoProfileSwitching.value) {
                    val metadata = TrackMetadata(genre = genre)
                    val recommendedProfile = determineOptimalProfile(metadata)
                    
                    if (recommendedProfile != _currentProfile.value) {
                        delay(2000) // Wait 2 seconds before switching
                        setAudioProfile(recommendedProfile)
                        Log.i(TAG, "Auto-switched to profile: $recommendedProfile based on genre: $genre")
                    }
                }
            }
        }
    }
    
    private fun stopAutoProfileSwitching() {
        // Auto switching is stopped by the coroutine scope check
    }
    
    // Getters for individual systems (for direct access if needed)
    fun getAdvancedEffects(): AdvancedAudioEffects = advancedEffects
    fun getSpatialAudio(): SpatialAudioSystem = spatialAudio
    fun getIntelligentEQ(): IntelligentAutoEQ = intelligentEQ
    fun getAudioAnalysis(): AudioAnalysisEngine = audioAnalysis
    
    private fun loadSettings() {
        _enhancedAudioEnabled.value = prefs.getBoolean(PREF_ENHANCED_AUDIO_ENABLED, false)
        
        val profileName = prefs.getString(PREF_CURRENT_PROFILE, AudioProfile.BALANCED.name)
        _currentProfile.value = AudioProfile.valueOf(profileName ?: AudioProfile.BALANCED.name)
        
        _autoProfileSwitching.value = prefs.getBoolean(PREF_AUTO_PROFILE_SWITCHING, false)
        _crossSystemSync.value = prefs.getBoolean(PREF_CROSS_SYSTEM_SYNC, true)
    }
}

enum class AudioProfile {
    AUDIOPHILE,
    BASS_BOOST,
    VOCAL_CLARITY,
    GAMING,
    CLASSICAL,
    ELECTRONIC,
    ROCK_METAL,
    JAZZ_ACOUSTIC,
    BALANCED,
    CUSTOM
}

data class TrackMetadata(
    val genre: String? = null,
    val artist: String? = null,
    val tempo: Float? = null,
    val year: Int? = null
)

data class OverallAudioState(
    val qualityRating: AudioQualityRating = AudioQualityRating.GOOD,
    val dynamicRange: Float = 12.0f,
    val spatialProcessingActive: Boolean = false,
    val effectsProcessingActive: Boolean = false,
    val intelligentEQActive: Boolean = false,
    val currentProfile: AudioProfile = AudioProfile.BALANCED,
    val processingLatency: Float = 5.0f,
    val recommendedProfile: AudioProfile? = null
)

data class SystemStatus(
    val advancedEffectsActive: Boolean = false,
    val spatialAudioActive: Boolean = false,
    val intelligentEQActive: Boolean = false,
    val audioAnalysisActive: Boolean = false,
    val overallCpuUsage: Float = 0.0f,
    val memoryUsage: Float = 0.0f
)