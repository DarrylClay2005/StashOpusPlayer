package com.stash.opusplayer.cloud.models

import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBAttribute
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBHashKey
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBRangeKey
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBTable
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

/**
 * DynamoDB model for tracking listening analytics and audio preferences
 * 
 * Table structure:
 * - userId (Hash Key): Unique user identifier
 * - timestamp (Range Key): Event timestamp for time-series data
 * - Contains detailed listening and audio processing data
 */
@DynamoDBTable(tableName = "StashOpusPlayer_ListeningAnalytics")
data class ListeningAnalytics(
    
    @DynamoDBHashKey(attributeName = "userId")
    var userId: String = "",
    
    @DynamoDBRangeKey(attributeName = "timestamp")
    var timestamp: Long = System.currentTimeMillis(),
    
    @DynamoDBAttribute(attributeName = "eventType")
    var eventType: String = "",
    
    @DynamoDBAttribute(attributeName = "songId")
    var songId: String = "",
    
    @DynamoDBAttribute(attributeName = "songTitle")
    var songTitle: String = "",
    
    @DynamoDBAttribute(attributeName = "artist")
    var artist: String = "",
    
    @DynamoDBAttribute(attributeName = "album")
    var album: String = "",
    
    @DynamoDBAttribute(attributeName = "genre")
    var genre: String = "",
    
    @DynamoDBAttribute(attributeName = "duration")
    var duration: Long = 0,
    
    @DynamoDBAttribute(attributeName = "playedDuration")
    var playedDuration: Long = 0,
    
    @DynamoDBAttribute(attributeName = "audioProfile")
    var audioProfile: String = "",
    
    @DynamoDBAttribute(attributeName = "equalizerPreset")
    var equalizerPreset: String = "",
    
    @DynamoDBAttribute(attributeName = "audioMetrics")
    var audioMetricsJson: String = "{}",
    
    @DynamoDBAttribute(attributeName = "deviceId")
    var deviceId: String = "",
    
    @DynamoDBAttribute(attributeName = "appVersion")
    var appVersion: String = "11.1.0",
    
    @DynamoDBAttribute(attributeName = "sessionId")
    var sessionId: String = ""
) {
    
    companion object {
        // Event types
        const val EVENT_SONG_STARTED = "song_started"
        const val EVENT_SONG_COMPLETED = "song_completed"
        const val EVENT_SONG_SKIPPED = "song_skipped"
        const val EVENT_PROFILE_CHANGED = "profile_changed"
        const val EVENT_EQUALIZER_ADJUSTED = "equalizer_adjusted"
        const val EVENT_EFFECT_TOGGLED = "effect_toggled"
        const val EVENT_SESSION_STARTED = "session_started"
        const val EVENT_SESSION_ENDED = "session_ended"
        
        private val gson = Gson()
    }
    
    /**
     * Convert audio metrics map to JSON string
     */
    fun setAudioMetrics(metrics: Map<String, Any>) {
        audioMetricsJson = gson.toJson(metrics)
    }
    
    /**
     * Parse JSON string back to audio metrics map
     */
    fun getAudioMetrics(): Map<String, Any> {
        return try {
            val type = object : TypeToken<Map<String, Any>>() {}.type
            gson.fromJson(audioMetricsJson, type) ?: emptyMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }
    
    /**
     * Add audio metric
     */
    fun addAudioMetric(key: String, value: Any) {
        val metrics = getAudioMetrics().toMutableMap()
        metrics[key] = value
        setAudioMetrics(metrics)
    }
    
    /**
     * Get completion percentage
     */
    fun getCompletionPercentage(): Float {
        return if (duration > 0) (playedDuration.toFloat() / duration.toFloat()) * 100f else 0f
    }
    
    /**
     * Check if song was completed (played more than 80%)
     */
    fun isCompleted(): Boolean {
        return getCompletionPercentage() >= 80f
    }
    
    /**
     * Check if song was skipped (played less than 20%)
     */
    fun isSkipped(): Boolean {
        return getCompletionPercentage() < 20f
    }
    
    /**
     * Create analytics event for song start
     */
    fun createSongStartedEvent(
        userId: String,
        songId: String,
        songTitle: String,
        artist: String,
        album: String,
        genre: String,
        duration: Long,
        audioProfile: String,
        equalizerPreset: String,
        deviceId: String,
        sessionId: String
    ): ListeningAnalytics {
        return ListeningAnalytics(
            userId = userId,
            timestamp = System.currentTimeMillis(),
            eventType = EVENT_SONG_STARTED,
            songId = songId,
            songTitle = songTitle,
            artist = artist,
            album = album,
            genre = genre,
            duration = duration,
            playedDuration = 0,
            audioProfile = audioProfile,
            equalizerPreset = equalizerPreset,
            deviceId = deviceId,
            sessionId = sessionId
        )
    }
    
    /**
     * Create analytics event for song completion
     */
    fun createSongCompletedEvent(
        songStartedEvent: ListeningAnalytics,
        playedDuration: Long,
        audioMetrics: Map<String, Any>
    ): ListeningAnalytics {
        val completedEvent = songStartedEvent.copy()
        completedEvent.timestamp = System.currentTimeMillis()
        completedEvent.eventType = EVENT_SONG_COMPLETED
        completedEvent.playedDuration = playedDuration
        completedEvent.setAudioMetrics(audioMetrics)
        return completedEvent
    }
    
    /**
     * Create analytics event for profile change
     */
    fun createProfileChangedEvent(
        userId: String,
        fromProfile: String,
        toProfile: String,
        deviceId: String,
        sessionId: String
    ): ListeningAnalytics {
        return ListeningAnalytics(
            userId = userId,
            timestamp = System.currentTimeMillis(),
            eventType = EVENT_PROFILE_CHANGED,
            audioProfile = toProfile,
            deviceId = deviceId,
            sessionId = sessionId
        ).apply {
            addAudioMetric("from_profile", fromProfile)
            addAudioMetric("to_profile", toProfile)
        }
    }
    
    /**
     * Get event age in hours
     */
    fun getAgeInHours(): Long {
        return (System.currentTimeMillis() - timestamp) / (1000 * 60 * 60)
    }
    
    /**
     * Check if event is recent (within last 24 hours)
     */
    fun isRecent(): Boolean {
        return getAgeInHours() <= 24
    }
    
    /**
     * Validate analytics data
     */
    fun isValid(): Boolean {
        return userId.isNotBlank() && 
               eventType.isNotBlank() && 
               timestamp > 0
    }
    
    override fun toString(): String {
        return "ListeningAnalytics(userId='$userId', timestamp=$timestamp, eventType='$eventType', songTitle='$songTitle', artist='$artist', audioProfile='$audioProfile', deviceId='$deviceId')"
    }
}