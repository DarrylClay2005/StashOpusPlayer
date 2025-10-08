package com.stash.opusplayer.cloud.repositories

import android.util.Log
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBMapper
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBQueryExpression
import com.amazonaws.services.dynamodbv2.model.AttributeValue
import com.amazonaws.services.dynamodbv2.model.ComparisonOperator
import com.amazonaws.services.dynamodbv2.model.Condition
import com.stash.opusplayer.cloud.models.ListeningAnalytics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/**
 * Repository for managing listening analytics in DynamoDB
 * 
 * Handles tracking and querying of user listening behavior and audio preferences
 */
class AnalyticsRepository(private val dynamoDBMapper: DynamoDBMapper) {
    
    companion object {
        private const val TAG = "AnalyticsRepository"
        private const val BATCH_SIZE = 25  // DynamoDB batch write limit
    }
    
    /**
     * Record a single analytics event
     */
    suspend fun recordEvent(event: ListeningAnalytics): Boolean = withContext(Dispatchers.IO) {
        try {
            if (!event.isValid()) {
                Log.w(TAG, "Invalid analytics event: $event")
                return@withContext false
            }
            
            dynamoDBMapper.save(event)
            Log.d(TAG, "Successfully recorded analytics event: ${event.eventType} for user: ${event.userId}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to record analytics event: ${event.eventType}", e)
            false
        }
    }
    
    /**
     * Record multiple analytics events in batch
     */
    suspend fun recordEvents(events: List<ListeningAnalytics>): Int = withContext(Dispatchers.IO) {
        var recordedCount = 0
        
        try {
            // Process events in batches to respect DynamoDB limits
            events.chunked(BATCH_SIZE).forEach { batch ->
                val validEvents = batch.filter { it.isValid() }
                
                if (validEvents.isNotEmpty()) {
                    try {
                        dynamoDBMapper.batchSave(validEvents)
                        recordedCount += validEvents.size
                        Log.d(TAG, "Successfully recorded batch of ${validEvents.size} events")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to record batch of events", e)
                        // Fallback to individual saves for this batch
                        validEvents.forEach { event ->
                            if (recordEvent(event)) {
                                recordedCount++
                            }
                        }
                    }
                }
            }
            
            Log.d(TAG, "Successfully recorded $recordedCount/${events.size} analytics events")
        } catch (e: Exception) {
            Log.e(TAG, "Error in batch record events", e)
        }
        
        recordedCount
    }
    
    /**
     * Get recent analytics events for a user
     */
    suspend fun getRecentEvents(userId: String, hours: Int = 24): List<ListeningAnalytics> = withContext(Dispatchers.IO) {
        try {
            val cutoffTime = System.currentTimeMillis() - TimeUnit.HOURS.toMillis(hours.toLong())
            
            val event = ListeningAnalytics()
            event.userId = userId
            
            val queryExpression = DynamoDBQueryExpression<ListeningAnalytics>()
                .withHashKeyValues(event)
                .withRangeKeyCondition(
                    "timestamp",
                    Condition()
                        .withComparisonOperator(ComparisonOperator.GE)
                        .withAttributeValueList(AttributeValue().withN(cutoffTime.toString()))
                )
                .withScanIndexForward(false) // Most recent first
                .withConsistentRead(false)
            
            val events = dynamoDBMapper.query(ListeningAnalytics::class.java, queryExpression)
            Log.d(TAG, "Successfully loaded ${events.size} recent events for user: $userId")
            events
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get recent events for user: $userId", e)
            emptyList()
        }
    }
    
    /**
     * Get analytics events by type
     */
    suspend fun getEventsByType(userId: String, eventType: String, limit: Int = 100): List<ListeningAnalytics> = withContext(Dispatchers.IO) {
        try {
            val recentEvents = getRecentEvents(userId, 168) // Last week
            val filteredEvents = recentEvents
                .filter { it.eventType == eventType }
                .take(limit)
            
            Log.d(TAG, "Found ${filteredEvents.size} events of type '$eventType' for user: $userId")
            filteredEvents
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get events by type: $eventType for user: $userId", e)
            emptyList()
        }
    }
    
    /**
     * Get listening statistics for a user
     */
    suspend fun getListeningStats(userId: String, days: Int = 7): Map<String, Any> = withContext(Dispatchers.IO) {
        try {
            val events = getRecentEvents(userId, days * 24)
            
            val stats = mutableMapOf<String, Any>()
            
            // Basic stats
            stats["total_events"] = events.size
            stats["period_days"] = days
            
            // Song statistics
            val songEvents = events.filter { it.eventType in listOf(
                ListeningAnalytics.EVENT_SONG_STARTED,
                ListeningAnalytics.EVENT_SONG_COMPLETED,
                ListeningAnalytics.EVENT_SONG_SKIPPED
            )}
            
            stats["songs_played"] = songEvents.count { it.eventType == ListeningAnalytics.EVENT_SONG_STARTED }
            stats["songs_completed"] = songEvents.count { it.eventType == ListeningAnalytics.EVENT_SONG_COMPLETED }
            stats["songs_skipped"] = songEvents.count { it.eventType == ListeningAnalytics.EVENT_SONG_SKIPPED }
            
            // Calculate completion rate
            val totalSongs = stats["songs_played"] as Int
            if (totalSongs > 0) {
                val completedSongs = stats["songs_completed"] as Int
                stats["completion_rate"] = (completedSongs.toFloat() / totalSongs.toFloat()) * 100f
            }
            
            // Total listening time
            val totalListeningTime = songEvents
                .filter { it.eventType == ListeningAnalytics.EVENT_SONG_COMPLETED }
                .sumOf { it.playedDuration }
            stats["total_listening_time_ms"] = totalListeningTime
            stats["total_listening_time_minutes"] = totalListeningTime / (1000 * 60)
            
            // Popular genres
            val genreCounts = songEvents
                .filter { it.genre.isNotBlank() }
                .groupingBy { it.genre }
                .eachCount()
            stats["popular_genres"] = genreCounts.toList().sortedByDescending { it.second }.take(5)
            
            // Popular artists
            val artistCounts = songEvents
                .filter { it.artist.isNotBlank() }
                .groupingBy { it.artist }
                .eachCount()
            stats["popular_artists"] = artistCounts.toList().sortedByDescending { it.second }.take(5)
            
            // Audio profile usage
            val profileEvents = events.filter { it.audioProfile.isNotBlank() }
            val profileCounts = profileEvents
                .groupingBy { it.audioProfile }
                .eachCount()
            stats["audio_profile_usage"] = profileCounts
            
            // Session statistics
            val sessionEvents = events.filter { it.eventType in listOf(
                ListeningAnalytics.EVENT_SESSION_STARTED,
                ListeningAnalytics.EVENT_SESSION_ENDED
            )}
            stats["sessions_started"] = sessionEvents.count { it.eventType == ListeningAnalytics.EVENT_SESSION_STARTED }
            stats["sessions_ended"] = sessionEvents.count { it.eventType == ListeningAnalytics.EVENT_SESSION_ENDED }
            
            Log.d(TAG, "Generated listening stats for user: $userId - $stats")
            stats
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get listening stats for user: $userId", e)
            emptyMap()
        }
    }
    
    /**
     * Get audio quality insights
     */
    suspend fun getAudioQualityInsights(userId: String, days: Int = 30): Map<String, Any> = withContext(Dispatchers.IO) {
        try {
            val events = getRecentEvents(userId, days * 24)
                .filter { it.eventType == ListeningAnalytics.EVENT_SONG_COMPLETED }
            
            val insights = mutableMapOf<String, Any>()
            
            if (events.isNotEmpty()) {
                val audioMetrics = events.mapNotNull { event ->
                    event.getAudioMetrics().takeIf { it.isNotEmpty() }
                }
                
                if (audioMetrics.isNotEmpty()) {
                    // Calculate average LUFS
                    val lufsValues = audioMetrics.mapNotNull { it["lufs"] as? Double }
                    if (lufsValues.isNotEmpty()) {
                        insights["avg_lufs"] = lufsValues.average()
                        insights["lufs_range"] = "${lufsValues.minOrNull()?.toString() ?: "N/A"} to ${lufsValues.maxOrNull()?.toString() ?: "N/A"}"
                    }
                    
                    // Calculate average dynamic range
                    val drValues = audioMetrics.mapNotNull { it["dynamic_range"] as? Double }
                    if (drValues.isNotEmpty()) {
                        insights["avg_dynamic_range"] = drValues.average()
                    }
                    
                    // Calculate average THD
                    val thdValues = audioMetrics.mapNotNull { it["thd"] as? Double }
                    if (thdValues.isNotEmpty()) {
                        insights["avg_thd"] = thdValues.average()
                    }
                }
            }
            
            insights["analyzed_songs"] = events.size
            insights["period_days"] = days
            
            Log.d(TAG, "Generated audio quality insights for user: $userId - $insights")
            insights
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get audio quality insights for user: $userId", e)
            emptyMap()
        }
    }
    
    /**
     * Clean up old analytics data
     */
    suspend fun cleanupOldData(userId: String, daysToKeep: Int = 90): Int = withContext(Dispatchers.IO) {
        try {
            val cutoffTime = System.currentTimeMillis() - TimeUnit.DAYS.toMillis(daysToKeep.toLong())
            
            val event = ListeningAnalytics()
            event.userId = userId
            
            val queryExpression = DynamoDBQueryExpression<ListeningAnalytics>()
                .withHashKeyValues(event)
                .withRangeKeyCondition(
                    "timestamp",
                    Condition()
                        .withComparisonOperator(ComparisonOperator.LT)
                        .withAttributeValueList(AttributeValue().withN(cutoffTime.toString()))
                )
                .withConsistentRead(false)
            
            val oldEvents = dynamoDBMapper.query(ListeningAnalytics::class.java, queryExpression)
            
            if (oldEvents.isNotEmpty()) {
                // Delete in batches
                oldEvents.chunked(BATCH_SIZE).forEach { batch ->
                    try {
                        dynamoDBMapper.batchDelete(batch)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to delete batch of old events", e)
                    }
                }
            }
            
            Log.d(TAG, "Cleaned up ${oldEvents.size} old analytics events for user: $userId")
            oldEvents.size
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup old data for user: $userId", e)
            0
        }
    }
    
    /**
     * Get top songs by play count
     */
    suspend fun getTopSongs(userId: String, limit: Int = 10, days: Int = 30): List<Pair<String, Int>> = withContext(Dispatchers.IO) {
        try {
            val events = getRecentEvents(userId, days * 24)
                .filter { it.eventType == ListeningAnalytics.EVENT_SONG_STARTED && it.songTitle.isNotBlank() }
            
            val songCounts = events
                .groupingBy { "${it.songTitle} - ${it.artist}" }
                .eachCount()
                .toList()
                .sortedByDescending { it.second }
                .take(limit)
            
            Log.d(TAG, "Found top ${songCounts.size} songs for user: $userId")
            songCounts
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get top songs for user: $userId", e)
            emptyList()
        }
    }
}