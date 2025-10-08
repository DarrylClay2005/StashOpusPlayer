package com.stash.opusplayer.cloud.models

import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBAttribute
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBHashKey
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBRangeKey
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBTable

/**
 * DynamoDB model for tracking device synchronization state
 * 
 * Table structure:
 * - userId (Hash Key): Unique user identifier
 * - deviceId (Range Key): Device identifier
 * - Tracks sync status, timestamps, and device metadata
 */
@DynamoDBTable(tableName = "StashOpusPlayer_DeviceSync")
data class DeviceSync(
    
    @DynamoDBHashKey(attributeName = "userId")
    var userId: String = "",
    
    @DynamoDBRangeKey(attributeName = "deviceId")
    var deviceId: String = "",
    
    @DynamoDBAttribute(attributeName = "deviceName")
    var deviceName: String = "",
    
    @DynamoDBAttribute(attributeName = "deviceModel")
    var deviceModel: String = "",
    
    @DynamoDBAttribute(attributeName = "androidVersion")
    var androidVersion: String = "",
    
    @DynamoDBAttribute(attributeName = "appVersion")
    var appVersion: String = "11.1.0",
    
    @DynamoDBAttribute(attributeName = "lastSyncAttempt")
    var lastSyncAttempt: Long = 0,
    
    @DynamoDBAttribute(attributeName = "lastSuccessfulSync")
    var lastSuccessfulSync: Long = 0,
    
    @DynamoDBAttribute(attributeName = "syncStatus")
    var syncStatus: String = SYNC_STATUS_PENDING,
    
    @DynamoDBAttribute(attributeName = "syncEnabled")
    var syncEnabled: Boolean = true,
    
    @DynamoDBAttribute(attributeName = "profilesSynced")
    var profilesSynced: Int = 0,
    
    @DynamoDBAttribute(attributeName = "analyticsEnabled")
    var analyticsEnabled: Boolean = true,
    
    @DynamoDBAttribute(attributeName = "lastActiveTime")
    var lastActiveTime: Long = System.currentTimeMillis(),
    
    @DynamoDBAttribute(attributeName = "syncErrors")
    var syncErrors: Int = 0,
    
    @DynamoDBAttribute(attributeName = "lastErrorMessage")
    var lastErrorMessage: String = "",
    
    @DynamoDBAttribute(attributeName = "registrationTime")
    var registrationTime: Long = System.currentTimeMillis()
) {
    
    companion object {
        // Sync status constants
        const val SYNC_STATUS_PENDING = "pending"
        const val SYNC_STATUS_IN_PROGRESS = "in_progress"
        const val SYNC_STATUS_SUCCESS = "success"
        const val SYNC_STATUS_ERROR = "error"
        const val SYNC_STATUS_DISABLED = "disabled"
        
        // Sync intervals in milliseconds
        const val SYNC_INTERVAL_FAST = 5 * 60 * 1000L      // 5 minutes
        const val SYNC_INTERVAL_NORMAL = 30 * 60 * 1000L    // 30 minutes
        const val SYNC_INTERVAL_SLOW = 2 * 60 * 60 * 1000L  // 2 hours
        
        // Error thresholds
        const val MAX_SYNC_ERRORS = 5
    }
    
    /**
     * Check if device is currently syncing
     */
    fun isSyncing(): Boolean {
        return syncStatus == SYNC_STATUS_IN_PROGRESS
    }
    
    /**
     * Check if sync is enabled and allowed
     */
    fun canSync(): Boolean {
        return syncEnabled && syncErrors < MAX_SYNC_ERRORS
    }
    
    /**
     * Check if device needs to sync based on last sync time
     */
    fun needsSync(intervalMs: Long = SYNC_INTERVAL_NORMAL): Boolean {
        if (!canSync()) return false
        
        val timeSinceLastSync = System.currentTimeMillis() - lastSuccessfulSync
        return timeSinceLastSync > intervalMs
    }
    
    /**
     * Mark sync as started
     */
    fun markSyncStarted() {
        lastSyncAttempt = System.currentTimeMillis()
        syncStatus = SYNC_STATUS_IN_PROGRESS
    }
    
    /**
     * Mark sync as successful
     */
    fun markSyncSuccess(profilesCount: Int) {
        lastSuccessfulSync = System.currentTimeMillis()
        syncStatus = SYNC_STATUS_SUCCESS
        profilesSynced = profilesCount
        syncErrors = 0
        lastErrorMessage = ""
        updateActivity()
    }
    
    /**
     * Mark sync as failed
     */
    fun markSyncError(errorMessage: String) {
        syncStatus = SYNC_STATUS_ERROR
        syncErrors++
        lastErrorMessage = errorMessage
        updateActivity()
    }
    
    /**
     * Update last active time
     */
    fun updateActivity() {
        lastActiveTime = System.currentTimeMillis()
    }
    
    /**
     * Reset sync errors
     */
    fun resetErrors() {
        syncErrors = 0
        lastErrorMessage = ""
        if (syncStatus == SYNC_STATUS_ERROR) {
            syncStatus = SYNC_STATUS_PENDING
        }
    }
    
    /**
     * Get recommended sync interval based on device activity
     */
    fun getRecommendedSyncInterval(): Long {
        val hoursInactive = (System.currentTimeMillis() - lastActiveTime) / (1000 * 60 * 60)
        
        return when {
            hoursInactive < 1 -> SYNC_INTERVAL_FAST     // Very active - sync frequently
            hoursInactive < 24 -> SYNC_INTERVAL_NORMAL   // Moderately active - normal sync
            else -> SYNC_INTERVAL_SLOW                   // Inactive - sync less frequently
        }
    }
    
    /**
     * Get sync health score (0-100)
     */
    fun getSyncHealthScore(): Int {
        if (!syncEnabled) return 0
        
        val errorPenalty = (syncErrors * 20).coerceAtMost(80)
        val baseScore = 100 - errorPenalty
        
        // Penalize for no successful syncs
        if (lastSuccessfulSync == 0L) {
            return baseScore / 2
        }
        
        // Penalize for stale syncs
        val hoursSinceSync = (System.currentTimeMillis() - lastSuccessfulSync) / (1000 * 60 * 60)
        val stalePenalty = when {
            hoursSinceSync > 168 -> 30  // More than a week
            hoursSinceSync > 24 -> 15   // More than a day
            hoursSinceSync > 2 -> 5     // More than 2 hours
            else -> 0
        }
        
        return (baseScore - stalePenalty).coerceAtLeast(0)
    }
    
    /**
     * Get sync status description for UI
     */
    fun getSyncStatusDescription(): String {
        return when (syncStatus) {
            SYNC_STATUS_PENDING -> "Ready to sync"
            SYNC_STATUS_IN_PROGRESS -> "Syncing..."
            SYNC_STATUS_SUCCESS -> {
                val hoursAgo = (System.currentTimeMillis() - lastSuccessfulSync) / (1000 * 60 * 60)
                when {
                    hoursAgo < 1 -> "Synced recently"
                    hoursAgo == 1L -> "Synced 1 hour ago"
                    hoursAgo < 24 -> "Synced $hoursAgo hours ago"
                    else -> "Synced ${hoursAgo / 24} days ago"
                }
            }
            SYNC_STATUS_ERROR -> "Sync failed: $lastErrorMessage"
            SYNC_STATUS_DISABLED -> "Sync disabled"
            else -> "Unknown status"
        }
    }
    
    /**
     * Check if device has been active recently
     */
    fun isActiveDevice(): Boolean {
        val hoursInactive = (System.currentTimeMillis() - lastActiveTime) / (1000 * 60 * 60)
        return hoursInactive < 48 // Active within last 2 days
    }
    
    /**
     * Get device display name
     */
    fun getDisplayName(): String {
        return if (deviceName.isNotBlank()) deviceName else deviceModel.ifBlank { "Unknown Device" }
    }
    
    /**
     * Validate device sync data
     */
    fun isValid(): Boolean {
        return userId.isNotBlank() && deviceId.isNotBlank()
    }
    
    override fun toString(): String {
        return "DeviceSync(userId='$userId', deviceId='$deviceId', deviceName='$deviceName', syncStatus='$syncStatus', lastSuccessfulSync=$lastSuccessfulSync, syncErrors=$syncErrors)"
    }
}