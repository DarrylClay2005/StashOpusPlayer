package com.stash.opusplayer.audio.service

import android.content.Context
import androidx.media3.common.MediaItem
import com.stash.opusplayer.audio.engine.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import timber.log.Timber
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
// import javax.inject.Inject
// import javax.inject.Singleton

/**
 * Enhanced Audio Telemetry System with 8D Audio Support
 * 
 * Revolutionary analytics engine with comprehensive 8D audio tracking:
 * - Real-time 8D performance monitoring
 * - Spatial audio usage analytics
 * - Advanced 8D audio quality metrics
 * - User behavior with 8D features
 * - AI-powered 8D optimization tracking
 */
// @Singleton
class Enhanced8DTelemetrySystem constructor(
    private val context: Context
) {
    
    companion object {
        private const val TELEMETRY_TAG = "Enhanced8DTelemetrySystem"
        private const val MAX_TELEMETRY_ENTRIES = 1000
        private const val TELEMETRY_FLUSH_INTERVAL_MS = 30000L // 30 seconds
    }
    
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val startTime = System.currentTimeMillis()
    
    // Real-time metrics
    private val _currentTelemetry = MutableStateFlow(Enhanced8DTelemetryData())
    val currentTelemetry: StateFlow<Enhanced8DTelemetryData> = _currentTelemetry.asStateFlow()
    
    // Performance counters
    private val tracksPlayedCounter = AtomicLong(0)
    private val userInteractionCounter = AtomicLong(0)
    private val profileChangeCounter = AtomicLong(0)
    private val aiOptimizationCounter = AtomicLong(0)
    private val errorCounter = AtomicLong(0)
    private val skipCounter = AtomicLong(0)
    private val seekCounter = AtomicLong(0)
    
    // 8D Audio specific counters
    private val audio8DToggleCounter = AtomicLong(0)
    private val audio8DIntensityAdjustmentCounter = AtomicLong(0)
    private val audio8DSpeedAdjustmentCounter = AtomicLong(0)
    private val audio8DPlaybackTimeMs = AtomicLong(0)
    
    // Advanced metrics storage
    private val audioMetricsHistory = mutableListOf<TimestampedAudioMetrics>()
    private val audio8DMetricsHistory = mutableListOf<Timestamped8DMetrics>()
    private val profileUsageStats = ConcurrentHashMap<String, ProfileUsageStats>()
    private val errorHistory = mutableListOf<TimestampedError>()
    private val userActionHistory = mutableListOf<TimestampedUserAction>()
    private val performanceMetrics = mutableListOf<TimestampedPerformanceMetric>()
    
    // Audio quality tracking
    private var totalPlaybackTimeMs = AtomicLong(0)
    private var buffersUnderruns = AtomicLong(0)
    private var audioDropouts = AtomicLong(0)
    
    fun initialize() {
        Timber.i("🚀 Enhanced 8D Audio Telemetry System initialized")
        startTelemetryCollection()
    }
    
    private fun startTelemetryCollection() {
        scope.launch {
            // Periodic telemetry updates
            while (isActive) {
                try {
                    updateCurrentTelemetry()
                    flushOldData()
                    delay(TELEMETRY_FLUSH_INTERVAL_MS)
                } catch (e: Exception) {
                    Timber.e(e, "Error in telemetry collection")
                }
            }
        }
    }
    
    private fun updateCurrentTelemetry() {
        _currentTelemetry.value = Enhanced8DTelemetryData(
            uptime = System.currentTimeMillis() - startTime,
            tracksPlayed = tracksPlayedCounter.get(),
            userInteractions = userInteractionCounter.get(),
            profileChanges = profileChangeCounter.get(),
            aiOptimizations = aiOptimizationCounter.get(),
            errorCount = errorCounter.get(),
            skipCount = skipCounter.get(),
            seekCount = seekCounter.get(),
            totalPlaybackTime = totalPlaybackTimeMs.get(),
            bufferUnderruns = buffersUnderruns.get(),
            audioDropouts = audioDropouts.get(),
            averageAudioQuality = calculateAverageAudioQuality(),
            mostUsedProfile = getMostUsedProfile(),
            systemPerformanceScore = calculateSystemPerformanceScore(),
            // 8D specific metrics
            audio8DToggleCount = audio8DToggleCounter.get(),
            audio8DIntensityAdjustments = audio8DIntensityAdjustmentCounter.get(),
            audio8DSpeedAdjustments = audio8DSpeedAdjustmentCounter.get(),
            audio8DPlaybackTime = audio8DPlaybackTimeMs.get(),
            average8DIntensity = calculateAverage8DIntensity(),
            average8DSpeed = calculateAverage8DSpeed(),
            audio8DUsagePercentage = calculate8DUsagePercentage()
        )
    }
    
    // 8D Audio telemetry methods
    fun record8DAudioState(enabled: Boolean) {
        recordUserAction("8D_AUDIO_STATE", enabled.toString())
        
        val timestamp = System.currentTimeMillis()
        performanceMetrics.add(
            TimestampedPerformanceMetric(
                timestamp = timestamp,
                metricType = "8D_ENABLED",
                value = if (enabled) 1.0f else 0.0f
            )
        )
        
        Timber.i("🌀 8D Audio ${if (enabled) "enabled" else "disabled"}")
    }
    
    fun record8DAudioIntensity(intensity: Float) {
        val timestamp = System.currentTimeMillis()
        
        val audio8DMetrics = Timestamped8DMetrics(
            timestamp = timestamp,
            intensity = intensity,
            speed = 1.0f, // Default speed if not provided
            enabled = true
        )
        
        synchronized(audio8DMetricsHistory) {
            audio8DMetricsHistory.add(audio8DMetrics)
            if (audio8DMetricsHistory.size > MAX_TELEMETRY_ENTRIES) {
                audio8DMetricsHistory.removeAt(0)
            }
        }
        
        performanceMetrics.add(
            TimestampedPerformanceMetric(
                timestamp = timestamp,
                metricType = "8D_INTENSITY",
                value = intensity
            )
        )
    }
    
    fun record8DAudioSpeed(speed: Float) {
        val timestamp = System.currentTimeMillis()
        performanceMetrics.add(
            TimestampedPerformanceMetric(
                timestamp = timestamp,
                metricType = "8D_SPEED",
                value = speed
            )
        )
    }
    
    fun record8DToggle(enabled: Boolean) {
        audio8DToggleCounter.incrementAndGet()
        recordUserAction("8D_TOGGLE", enabled.toString())
        Timber.i("🎚️ 8D Audio toggled: ${if (enabled) "ON" else "OFF"}")
    }
    
    fun record8DIntensityChange(intensity: Float) {
        audio8DIntensityAdjustmentCounter.incrementAndGet()
        recordUserAction("8D_INTENSITY_CHANGE", intensity.toString())
        Timber.d("🎯 8D Intensity changed to: ${(intensity * 100).toInt()}%")
    }
    
    fun record8DSpeedChange(speed: Float) {
        audio8DSpeedAdjustmentCounter.incrementAndGet()
        recordUserAction("8D_SPEED_CHANGE", speed.toString())
        Timber.d("🌪️ 8D Speed changed to: ${speed}x")
    }
    
    fun record8DPlaybackTime(durationMs: Long) {
        audio8DPlaybackTimeMs.addAndGet(durationMs)
    }
    
    // Standard telemetry methods
    fun recordPlaybackState(state: AudioEngine.Companion.PlaybackState) {
        when (state) {
            AudioEngine.Companion.PlaybackState.PLAYING -> {
                val timestamp = System.currentTimeMillis()
                performanceMetrics.add(
                    TimestampedPerformanceMetric(
                        timestamp = timestamp,
                        metricType = "PLAYBACK_START",
                        value = 1.0f
                    )
                )
            }
            AudioEngine.Companion.PlaybackState.ERROR -> {
                errorCounter.incrementAndGet()
            }
            else -> { /* Handle other states if needed */ }
        }
    }
    
    fun recordTrackChange(mediaItem: MediaItem?) {
        tracksPlayedCounter.incrementAndGet()
        
        if (mediaItem != null) {
            val genre = mediaItem.mediaMetadata.genre?.toString() ?: "Unknown"
            val artist = mediaItem.mediaMetadata.artist?.toString() ?: "Unknown"
            val title = mediaItem.mediaMetadata.title?.toString() ?: "Unknown"
            
            Timber.i("🎵 Track: $title by $artist ($genre) - Total played: ${tracksPlayedCounter.get()}")
        }
    }
    
    fun recordAudioMetrics(metrics: RevolutionaryAudioProcessor.AudioMetrics) {
        val timestamped = TimestampedAudioMetrics(
            timestamp = System.currentTimeMillis(),
            metrics = metrics
        )
        
        synchronized(audioMetricsHistory) {
            audioMetricsHistory.add(timestamped)
            if (audioMetricsHistory.size > MAX_TELEMETRY_ENTRIES) {
                audioMetricsHistory.removeAt(0)
            }
        }
    }
    
    fun recordFrequencySpectrum(spectrum: FloatArray) {
        val bassEnergy = spectrum.take(128).average().toFloat()
        val midEnergy = spectrum.drop(128).take(512).average().toFloat()
        val trebleEnergy = spectrum.drop(640).average().toFloat()
        
        val timestamp = System.currentTimeMillis()
        performanceMetrics.addAll(listOf(
            TimestampedPerformanceMetric(timestamp, "SPECTRUM_BASS", bassEnergy),
            TimestampedPerformanceMetric(timestamp, "SPECTRUM_MID", midEnergy),
            TimestampedPerformanceMetric(timestamp, "SPECTRUM_TREBLE", trebleEnergy)
        ))
    }
    
    fun recordProfileChange(profile: RevolutionaryAudioProcessor.AudioProfile) {
        profileChangeCounter.incrementAndGet()
        
        val profileName = profile.name
        val stats = profileUsageStats.getOrPut(profileName) {
            ProfileUsageStats(profileName, 0, 0, System.currentTimeMillis())
        }
        
        profileUsageStats[profileName] = stats.copy(
            usageCount = stats.usageCount + 1,
            totalTimeUsed = stats.totalTimeUsed + (System.currentTimeMillis() - stats.lastUsed),
            lastUsed = System.currentTimeMillis()
        )
        
        Timber.i("🎨 Profile changed to: $profileName (${stats.usageCount + 1} times used)")
    }
    
    fun recordManualProfileChange(profile: RevolutionaryAudioProcessor.AudioProfile) {
        recordProfileChange(profile)
        recordUserAction("MANUAL_PROFILE_CHANGE", profile.name)
    }
    
    fun recordManualAdjustment(type: String, value: Float) {
        recordUserAction("MANUAL_ADJUSTMENT", "$type:$value")
        
        val timestamp = System.currentTimeMillis()
        performanceMetrics.add(
            TimestampedPerformanceMetric(
                timestamp = timestamp,
                metricType = "MANUAL_$type",
                value = value
            )
        )
    }
    
    fun recordPlaylistChange(size: Int) {
        recordUserAction("PLAYLIST_CHANGE", size.toString())
        
        val timestamp = System.currentTimeMillis()
        performanceMetrics.add(
            TimestampedPerformanceMetric(
                timestamp = timestamp,
                metricType = "PLAYLIST_SIZE",
                value = size.toFloat()
            )
        )
    }
    
    fun recordUserAction(action: String, extra: String = "") {
        userInteractionCounter.incrementAndGet()
        
        val timestamped = TimestampedUserAction(
            timestamp = System.currentTimeMillis(),
            action = action,
            extra = extra
        )
        
        synchronized(userActionHistory) {
            userActionHistory.add(timestamped)
            if (userActionHistory.size > MAX_TELEMETRY_ENTRIES) {
                userActionHistory.removeAt(0)
            }
        }
        
        when (action) {
            "NEXT", "PREVIOUS" -> skipCounter.incrementAndGet()
            "SEEK" -> seekCounter.incrementAndGet()
        }
        
        Timber.d("👤 User action: $action $extra")
    }
    
    fun recordError(error: Throwable) {
        errorCounter.incrementAndGet()
        
        val timestamped = TimestampedError(
            timestamp = System.currentTimeMillis(),
            errorType = error::class.java.simpleName,
            errorMessage = error.message ?: "Unknown error",
            stackTrace = error.stackTrace.take(5).joinToString("\n") { it.toString() }
        )
        
        synchronized(errorHistory) {
            errorHistory.add(timestamped)
            if (errorHistory.size > MAX_TELEMETRY_ENTRIES) {
                errorHistory.removeAt(0)
            }
        }
        
        Timber.e(error, "🚨 Error recorded: ${error::class.java.simpleName}")
    }
    
    fun recordBufferUnderrun() {
        buffersUnderruns.incrementAndGet()
        recordPerformanceIssue("BUFFER_UNDERRUN", 1.0f)
    }
    
    fun recordAudioDropout() {
        audioDropouts.incrementAndGet()
        recordPerformanceIssue("AUDIO_DROPOUT", 1.0f)
    }
    
    private fun recordPerformanceIssue(type: String, severity: Float) {
        val timestamp = System.currentTimeMillis()
        performanceMetrics.add(
            TimestampedPerformanceMetric(
                timestamp = timestamp,
                metricType = type,
                value = severity
            )
        )
    }
    
    // 8D specific analytics
    private fun calculateAverage8DIntensity(): Float {
        return synchronized(audio8DMetricsHistory) {
            if (audio8DMetricsHistory.isEmpty()) return@synchronized 0.7f
            
            audio8DMetricsHistory.map { it.intensity }.average().toFloat()
        }
    }
    
    private fun calculateAverage8DSpeed(): Float {
        return synchronized(audio8DMetricsHistory) {
            if (audio8DMetricsHistory.isEmpty()) return@synchronized 1.0f
            
            audio8DMetricsHistory.map { it.speed }.average().toFloat()
        }
    }
    
    private fun calculate8DUsagePercentage(): Float {
        if (totalPlaybackTimeMs.get() == 0L) return 0.0f
        
        return (audio8DPlaybackTimeMs.get().toFloat() / totalPlaybackTimeMs.get().toFloat()) * 100f
    }
    
    // Standard analytics methods
    private fun calculateAverageAudioQuality(): Float {
        return synchronized(audioMetricsHistory) {
            if (audioMetricsHistory.isEmpty()) return@synchronized 0.7f
            
            val recentMetrics = audioMetricsHistory.takeLast(100)
            val qualityScore = recentMetrics.map { metrics ->
                val dynamicRange = metrics.metrics.dynamicRange
                val stereoWidth = metrics.metrics.stereoWidth
                val loudness = metrics.metrics.loudness
                
                (dynamicRange + stereoWidth + loudness) / 3.0f
            }.average().toFloat()
            
            qualityScore.coerceIn(0.0f, 1.0f)
        }
    }
    
    private fun getMostUsedProfile(): String {
        return profileUsageStats.maxByOrNull { it.value.usageCount }?.key ?: "AUDIOPHILE_REFERENCE"
    }
    
    private fun calculateSystemPerformanceScore(): Float {
        val recentPerformanceIssues = synchronized(performanceMetrics) {
            val cutoffTime = System.currentTimeMillis() - 300000 // Last 5 minutes
            performanceMetrics.count { 
                it.timestamp > cutoffTime && 
                (it.metricType == "BUFFER_UNDERRUN" || it.metricType == "AUDIO_DROPOUT")
            }
        }
        
        val score = 1.0f - (recentPerformanceIssues * 0.1f).coerceAtMost(1.0f)
        return score.coerceIn(0.0f, 1.0f)
    }
    
    private fun flushOldData() {
        val cutoffTime = System.currentTimeMillis() - 3600000 // 1 hour
        
        synchronized(audioMetricsHistory) {
            audioMetricsHistory.removeAll { it.timestamp < cutoffTime }
        }
        
        synchronized(audio8DMetricsHistory) {
            audio8DMetricsHistory.removeAll { it.timestamp < cutoffTime }
        }
        
        synchronized(errorHistory) {
            errorHistory.removeAll { it.timestamp < cutoffTime }
        }
        
        synchronized(userActionHistory) {
            userActionHistory.removeAll { it.timestamp < cutoffTime }
        }
        
        synchronized(performanceMetrics) {
            performanceMetrics.removeAll { it.timestamp < cutoffTime }
        }
    }
    
    // Public API
    fun getCurrentTelemetry(): Enhanced8DTelemetryData = _currentTelemetry.value
    
    fun getDetailed8DAnalytics(): Detailed8DAnalytics {
        return Detailed8DAnalytics(
            telemetryData = getCurrentTelemetry(),
            profileUsageStats = profileUsageStats.values.toList(),
            recentErrors = synchronized(errorHistory) { errorHistory.takeLast(10) },
            recentUserActions = synchronized(userActionHistory) { userActionHistory.takeLast(20) },
            audioQualityTrend = getAudioQualityTrend(),
            performanceInsights = getPerformanceInsights(),
            audio8DInsights = get8DAudioInsights()
        )
    }
    
    private fun getAudioQualityTrend(): List<Float> {
        return synchronized(audioMetricsHistory) {
            audioMetricsHistory.takeLast(50).map { metrics ->
                (metrics.metrics.dynamicRange + metrics.metrics.stereoWidth + metrics.metrics.loudness) / 3.0f
            }
        }
    }
    
    private fun getPerformanceInsights(): List<String> {
        val insights = mutableListOf<String>()
        val telemetry = getCurrentTelemetry()
        
        if (telemetry.systemPerformanceScore > 0.9f) {
            insights.add("🎆 Excellent system performance! Audio quality is optimal.")
        } else if (telemetry.systemPerformanceScore < 0.5f) {
            insights.add("⚠️ Performance issues detected. Consider optimizing audio settings.")
        }
        
        if (telemetry.tracksPlayed > 100) {
            insights.add("🎵 You're a music enthusiast! ${telemetry.tracksPlayed} tracks played.")
        }
        
        val mostUsedProfile = getMostUsedProfile()
        insights.add("🎨 Your favorite audio profile: ${mostUsedProfile.replace("_", " ")}")
        
        if (telemetry.errorCount == 0L) {
            insights.add("✅ Perfect stability! No errors detected.")
        } else if (telemetry.errorCount > 10) {
            insights.add("🔧 High error rate detected. System diagnostics recommended.")
        }
        
        return insights
    }
    
    private fun get8DAudioInsights(): List<String> {
        val insights = mutableListOf<String>()
        val telemetry = getCurrentTelemetry()
        
        if (telemetry.audio8DUsagePercentage > 50f) {
            insights.add("🌀 You're an 8D audio enthusiast! ${telemetry.audio8DUsagePercentage.toInt()}% usage.")
        }
        
        if (telemetry.audio8DToggleCount > 20) {
            insights.add("🎚️ You like to experiment with 8D settings! ${telemetry.audio8DToggleCount} toggles.")
        }
        
        val avgIntensity = telemetry.average8DIntensity
        when {
            avgIntensity > 0.8f -> insights.add("🔥 You prefer intense 8D effects!")
            avgIntensity < 0.3f -> insights.add("🌊 You prefer subtle 8D effects.")
            else -> insights.add("⚖️ You have balanced 8D preferences.")
        }
        
        val avgSpeed = telemetry.average8DSpeed
        when {
            avgSpeed > 1.5f -> insights.add("🌪️ You love fast-paced 8D rotation!")
            avgSpeed < 0.7f -> insights.add("🐌 You prefer slow, cinematic 8D movement.")
            else -> insights.add("🎯 You stick to standard 8D rotation speeds.")
        }
        
        return insights
    }
    
    fun exportTelemetryData(): String {
        val analytics = getDetailed8DAnalytics()
        return "Revolutionary 8D Audio Telemetry Report\n" +
                "=========================================\n" +
                "Uptime: ${analytics.telemetryData.uptime / 1000}s\n" +
                "Tracks Played: ${analytics.telemetryData.tracksPlayed}\n" +
                "User Interactions: ${analytics.telemetryData.userInteractions}\n" +
                "Profile Changes: ${analytics.telemetryData.profileChanges}\n" +
                "AI Optimizations: ${analytics.telemetryData.aiOptimizations}\n" +
                "System Performance: ${(analytics.telemetryData.systemPerformanceScore * 100).toInt()}%\n" +
                "Audio Quality: ${(analytics.telemetryData.averageAudioQuality * 100).toInt()}%\n" +
                "Most Used Profile: ${analytics.telemetryData.mostUsedProfile}\n" +
                "\n8D Audio Statistics:\n" +
                "8D Toggles: ${analytics.telemetryData.audio8DToggleCount}\n" +
                "8D Usage: ${analytics.telemetryData.audio8DUsagePercentage.toInt()}%\n" +
                "Average Intensity: ${(analytics.telemetryData.average8DIntensity * 100).toInt()}%\n" +
                "Average Speed: ${analytics.telemetryData.average8DSpeed}x\n" +
                "\nInsights:\n" +
                analytics.performanceInsights.joinToString("\n") +
                "\n\n8D Audio Insights:\n" +
                analytics.audio8DInsights.joinToString("\n")
    }
    
    fun revolutionaryShutdown() {
        try {
            val finalReport = exportTelemetryData()
            Timber.i("Final 8D Telemetry Report:\n$finalReport")
            
            scope.cancel()
            
            // Clear all data
            audioMetricsHistory.clear()
            audio8DMetricsHistory.clear()
            profileUsageStats.clear()
            errorHistory.clear()
            userActionHistory.clear()
            performanceMetrics.clear()
            
            Timber.i("📊 ENHANCED 8D TELEMETRY SHUTDOWN COMPLETE")
            
        } catch (e: Exception) {
            Timber.e(e, "Error during telemetry shutdown")
        }
    }
    
    // Data classes
    data class Enhanced8DTelemetryData(
        val uptime: Long = 0,
        val tracksPlayed: Long = 0,
        val userInteractions: Long = 0,
        val profileChanges: Long = 0,
        val aiOptimizations: Long = 0,
        val errorCount: Long = 0,
        val skipCount: Long = 0,
        val seekCount: Long = 0,
        val totalPlaybackTime: Long = 0,
        val bufferUnderruns: Long = 0,
        val audioDropouts: Long = 0,
        val averageAudioQuality: Float = 0.0f,
        val mostUsedProfile: String = "",
        val systemPerformanceScore: Float = 0.0f,
        // 8D specific metrics
        val audio8DToggleCount: Long = 0,
        val audio8DIntensityAdjustments: Long = 0,
        val audio8DSpeedAdjustments: Long = 0,
        val audio8DPlaybackTime: Long = 0,
        val average8DIntensity: Float = 0.0f,
        val average8DSpeed: Float = 0.0f,
        val audio8DUsagePercentage: Float = 0.0f
    )
    
    data class Timestamped8DMetrics(
        val timestamp: Long,
        val intensity: Float,
        val speed: Float,
        val enabled: Boolean
    )
    
    data class ProfileUsageStats(
        val profileName: String,
        val usageCount: Long,
        val totalTimeUsed: Long,
        val lastUsed: Long
    )
    
    data class TimestampedAudioMetrics(
        val timestamp: Long,
        val metrics: RevolutionaryAudioProcessor.AudioMetrics
    )
    
    data class TimestampedError(
        val timestamp: Long,
        val errorType: String,
        val errorMessage: String,
        val stackTrace: String
    )
    
    data class TimestampedUserAction(
        val timestamp: Long,
        val action: String,
        val extra: String
    )
    
    data class TimestampedPerformanceMetric(
        val timestamp: Long,
        val metricType: String,
        val value: Float
    )
    
    data class Detailed8DAnalytics(
        val telemetryData: Enhanced8DTelemetryData,
        val profileUsageStats: List<ProfileUsageStats>,
        val recentErrors: List<TimestampedError>,
        val recentUserActions: List<TimestampedUserAction>,
        val audioQualityTrend: List<Float>,
        val performanceInsights: List<String>,
        val audio8DInsights: List<String>
    )
}