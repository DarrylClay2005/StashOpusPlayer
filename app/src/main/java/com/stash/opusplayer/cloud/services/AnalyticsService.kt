package com.stash.opusplayer.cloud.services

import android.content.Context
import android.util.Log
import com.stash.opusplayer.audio.settings.EnhancedAudioSettings
import com.stash.opusplayer.cloud.AWSConfig
import com.stash.opusplayer.cloud.models.ListeningAnalytics
import com.stash.opusplayer.cloud.repositories.AnalyticsRepository
import com.stash.opusplayer.data.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * Service for collecting and managing listening analytics
 * 
 * Tracks user behavior, audio preferences, and listening patterns
 */
class AnalyticsService private constructor(private val context: Context) {
    
    companion object {
        private const val TAG = "AnalyticsService"
        
        @Volatile
        private var INSTANCE: AnalyticsService? = null
        
        fun getInstance(context: Context): AnalyticsService {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: AnalyticsService(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
    
    private val awsConfig = AWSConfig.getInstance(context)
    private val enhancedAudioSettings = EnhancedAudioSettings(context)
    private val analyticsScope = CoroutineScope(Dispatchers.IO)
    
    private var analyticsRepository: AnalyticsRepository? = null
    private var isInitialized = false
    private var currentSessionId = generateSessionId()
    private var sessionStartTime = System.currentTimeMillis()
    
    // Current song tracking
    private var currentSongEvent: ListeningAnalytics? = null
    private var songStartTime = 0L
    
    /**
     * Initialize the analytics service
     */
    suspend fun initialize(): Boolean {
        return try {
            if (!awsConfig.isInitialized()) {
                if (!awsConfig.initialize()) {
                    Log.w(TAG, "AWS not initialized, analytics will be local only")
                    isInitialized = true // Allow local analytics even without cloud
                    return true
                }
            }
            
            val dynamoDBMapper = awsConfig.getDynamoDBMapper()
            if (dynamoDBMapper != null) {
                analyticsRepository = AnalyticsRepository(dynamoDBMapper)
                
                // Record session start
                recordSessionStart()
                
                isInitialized = true
                Log.d(TAG, "Analytics service initialized successfully")
                true
            } else {
                Log.w(TAG, "DynamoDB mapper not available, using local analytics only")
                isInitialized = true
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize analytics service", e)
            isInitialized = true // Continue with local analytics
            true
        }
    }
    
    /**
     * Record when a song starts playing
     */
    fun recordSongStarted(song: Song) {
        if (!isInitialized) return
        
        analyticsScope.launch {
            try {
                songStartTime = System.currentTimeMillis()
                
                val event = ListeningAnalytics(
                    userId = awsConfig.getUserId(),
                    timestamp = songStartTime,
                    eventType = ListeningAnalytics.EVENT_SONG_STARTED,
                    songId = song.id.toString(),
                    songTitle = song.displayName,
                    artist = song.artistName,
                    album = song.albumName,
                    genre = song.genre,
                    duration = song.duration,
                    playedDuration = 0,
                    audioProfile = enhancedAudioSettings.getCurrentAudioProfile(),
                    equalizerPreset = enhancedAudioSettings.getEnhancedEqualizerPreset(),
                    deviceId = awsConfig.getDeviceId(),
                    sessionId = currentSessionId
                )
                
                currentSongEvent = event
                
                // Record to cloud if available
                analyticsRepository?.recordEvent(event)
                
                Log.d(TAG, "Recorded song started: ${song.displayName}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to record song started", e)
            }
        }
    }
    
    /**
     * Record when a song finishes or is stopped
     */
    fun recordSongCompleted(song: Song, actualPlayedDuration: Long? = null) {
        if (!isInitialized || currentSongEvent == null) return
        
        analyticsScope.launch {
            try {
                val playedDuration = actualPlayedDuration ?: (System.currentTimeMillis() - songStartTime)
                val currentEvent = currentSongEvent!!
                
                // Calculate audio metrics
                val audioMetrics = mutableMapOf<String, Any>()
                audioMetrics["played_duration"] = playedDuration
                audioMetrics["completion_percentage"] = if (song.duration > 0) {
                    (playedDuration.toFloat() / song.duration.toFloat()) * 100f
                } else 0f
                audioMetrics["stereo_width"] = enhancedAudioSettings.getStereoWidth()
                audioMetrics["tube_warmth"] = enhancedAudioSettings.getTubeWarmth()
                audioMetrics["compression_enabled"] = enhancedAudioSettings.isCompressionEnabled()
                audioMetrics["spectrum_analyzer_enabled"] = enhancedAudioSettings.isSpectrumAnalyzerEnabled()
                
                val completedEvent = ListeningAnalytics(
                    userId = currentEvent.userId,
                    timestamp = System.currentTimeMillis(),
                    eventType = if (playedDuration < song.duration * 0.2) {
                        ListeningAnalytics.EVENT_SONG_SKIPPED
                    } else {
                        ListeningAnalytics.EVENT_SONG_COMPLETED
                    },
                    songId = currentEvent.songId,
                    songTitle = currentEvent.songTitle,
                    artist = currentEvent.artist,
                    album = currentEvent.album,
                    genre = currentEvent.genre,
                    duration = currentEvent.duration,
                    playedDuration = playedDuration,
                    audioProfile = enhancedAudioSettings.getCurrentAudioProfile(),
                    equalizerPreset = enhancedAudioSettings.getEnhancedEqualizerPreset(),
                    deviceId = awsConfig.getDeviceId(),
                    sessionId = currentSessionId
                ).apply {
                    setAudioMetrics(audioMetrics)
                }
                
                // Record to cloud if available
                analyticsRepository?.recordEvent(completedEvent)
                
                currentSongEvent = null
                Log.d(TAG, "Recorded song completed: ${song.displayName} (${playedDuration}ms)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to record song completed", e)
            }
        }
    }
    
    /**
     * Record when an audio profile is changed
     */
    fun recordProfileChanged(fromProfile: String, toProfile: String) {
        if (!isInitialized) return
        
        analyticsScope.launch {
            try {
                val event = ListeningAnalytics(
                    userId = awsConfig.getUserId(),
                    timestamp = System.currentTimeMillis(),
                    eventType = ListeningAnalytics.EVENT_PROFILE_CHANGED,
                    audioProfile = toProfile,
                    deviceId = awsConfig.getDeviceId(),
                    sessionId = currentSessionId
                ).apply {
                    addAudioMetric("from_profile", fromProfile)
                    addAudioMetric("to_profile", toProfile)
                }
                
                // Record to cloud if available
                analyticsRepository?.recordEvent(event)
                
                Log.d(TAG, "Recorded profile changed: $fromProfile -> $toProfile")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to record profile changed", e)
            }
        }
    }
    
    /**
     * Record when equalizer settings are adjusted
     */
    fun recordEqualizerAdjusted(preset: String, customLevels: String = "") {
        if (!isInitialized) return
        
        analyticsScope.launch {
            try {
                val event = ListeningAnalytics(
                    userId = awsConfig.getUserId(),
                    timestamp = System.currentTimeMillis(),
                    eventType = ListeningAnalytics.EVENT_EQUALIZER_ADJUSTED,
                    equalizerPreset = preset,
                    audioProfile = enhancedAudioSettings.getCurrentAudioProfile(),
                    deviceId = awsConfig.getDeviceId(),
                    sessionId = currentSessionId
                ).apply {
                    if (customLevels.isNotEmpty()) {
                        addAudioMetric("custom_levels", customLevels)
                    }
                    addAudioMetric("spectrum_analyzer_enabled", enhancedAudioSettings.isSpectrumAnalyzerEnabled())
                }
                
                // Record to cloud if available
                analyticsRepository?.recordEvent(event)
                
                Log.d(TAG, "Recorded equalizer adjusted: $preset")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to record equalizer adjusted", e)
            }
        }
    }
    
    /**
     * Record when an audio effect is toggled on/off
     */
    fun recordEffectToggled(effectName: String, enabled: Boolean) {
        if (!isInitialized) return
        
        analyticsScope.launch {
            try {
                val event = ListeningAnalytics(
                    userId = awsConfig.getUserId(),
                    timestamp = System.currentTimeMillis(),
                    eventType = ListeningAnalytics.EVENT_EFFECT_TOGGLED,
                    audioProfile = enhancedAudioSettings.getCurrentAudioProfile(),
                    deviceId = awsConfig.getDeviceId(),
                    sessionId = currentSessionId
                ).apply {
                    addAudioMetric("effect_name", effectName)
                    addAudioMetric("enabled", enabled)
                }
                
                // Record to cloud if available
                analyticsRepository?.recordEvent(event)
                
                Log.d(TAG, "Recorded effect toggled: $effectName = $enabled")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to record effect toggled", e)
            }
        }
    }
    
    /**
     * Record session start
     */
    private suspend fun recordSessionStart() {
        try {
            val event = ListeningAnalytics(
                userId = awsConfig.getUserId(),
                timestamp = sessionStartTime,
                eventType = ListeningAnalytics.EVENT_SESSION_STARTED,
                audioProfile = enhancedAudioSettings.getCurrentAudioProfile(),
                equalizerPreset = enhancedAudioSettings.getEnhancedEqualizerPreset(),
                deviceId = awsConfig.getDeviceId(),
                sessionId = currentSessionId
            ).apply {
                addAudioMetric("professional_processor_enabled", enhancedAudioSettings.isProfessionalProcessorEnabled())
                addAudioMetric("spectrum_analyzer_enabled", enhancedAudioSettings.isSpectrumAnalyzerEnabled())
                addAudioMetric("enhanced_eq_enabled", enhancedAudioSettings.isEnhancedEqualizerEnabled())
            }
            
            analyticsRepository?.recordEvent(event)
            Log.d(TAG, "Recorded session started: $currentSessionId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to record session started", e)
        }
    }
    
    /**
     * Record session end
     */
    fun recordSessionEnd() {
        if (!isInitialized) return
        
        analyticsScope.launch {
            try {
                val sessionDuration = System.currentTimeMillis() - sessionStartTime
                
                val event = ListeningAnalytics(
                    userId = awsConfig.getUserId(),
                    timestamp = System.currentTimeMillis(),
                    eventType = ListeningAnalytics.EVENT_SESSION_ENDED,
                    deviceId = awsConfig.getDeviceId(),
                    sessionId = currentSessionId
                ).apply {
                    addAudioMetric("session_duration_ms", sessionDuration)
                    addAudioMetric("session_duration_minutes", sessionDuration / (1000 * 60))
                }
                
                analyticsRepository?.recordEvent(event)
                Log.d(TAG, "Recorded session ended: $currentSessionId (${sessionDuration}ms)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to record session ended", e)
            }
        }
    }
    
    /**
     * Get listening statistics
     */
    suspend fun getListeningStats(days: Int = 7): Map<String, Any> {
        return try {
            if (analyticsRepository != null) {
                analyticsRepository!!.getListeningStats(awsConfig.getUserId(), days)
            } else {
                emptyMap()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get listening stats", e)
            emptyMap()
        }
    }
    
    /**
     * Get audio quality insights
     */
    suspend fun getAudioQualityInsights(days: Int = 30): Map<String, Any> {
        return try {
            if (analyticsRepository != null) {
                analyticsRepository!!.getAudioQualityInsights(awsConfig.getUserId(), days)
            } else {
                emptyMap()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get audio quality insights", e)
            emptyMap()
        }
    }
    
    /**
     * Get top songs
     */
    suspend fun getTopSongs(limit: Int = 10, days: Int = 30): List<Pair<String, Int>> {
        return try {
            if (analyticsRepository != null) {
                analyticsRepository!!.getTopSongs(awsConfig.getUserId(), limit, days)
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get top songs", e)
            emptyList()
        }
    }
    
    /**
     * Clean up old analytics data
     */
    suspend fun cleanupOldData(daysToKeep: Int = 90): Int {
        return try {
            if (analyticsRepository != null) {
                analyticsRepository!!.cleanupOldData(awsConfig.getUserId(), daysToKeep)
            } else {
                0
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup old data", e)
            0
        }
    }
    
    /**
     * Generate a new session ID
     */
    private fun generateSessionId(): String {
        return UUID.randomUUID().toString()
    }
    
    /**
     * Start a new session (call when app comes to foreground)
     */
    fun startNewSession() {
        currentSessionId = generateSessionId()
        sessionStartTime = System.currentTimeMillis()
        
        if (isInitialized) {
            analyticsScope.launch {
                recordSessionStart()
            }
        }
        
        Log.d(TAG, "Started new session: $currentSessionId")
    }
    
    /**
     * Check if analytics is enabled (respects user privacy settings)
     */
    fun isAnalyticsEnabled(): Boolean {
        // Check user privacy preferences
        val prefs = context.getSharedPreferences("privacy_settings", Context.MODE_PRIVATE)
        return prefs.getBoolean("analytics_enabled", true) && isInitialized
    }
    
    /**
     * Enable or disable analytics collection
     */
    fun setAnalyticsEnabled(enabled: Boolean) {
        val prefs = context.getSharedPreferences("privacy_settings", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("analytics_enabled", enabled).apply()
        
        Log.d(TAG, "Analytics enabled set to: $enabled")
    }
    
    /**
     * Get current session ID
     */
    fun getCurrentSessionId(): String = currentSessionId
    
    /**
     * Clean up resources
     */
    fun cleanup() {
        recordSessionEnd()
        Log.d(TAG, "Analytics service cleaned up")
    }
}