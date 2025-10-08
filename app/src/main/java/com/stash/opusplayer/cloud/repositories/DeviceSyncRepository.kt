package com.stash.opusplayer.cloud.repositories

import android.util.Log
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBMapper
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBQueryExpression
import com.stash.opusplayer.cloud.models.DeviceSync
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Repository for managing device synchronization state in DynamoDB
 * 
 * Handles device registration, sync status tracking, and device management
 */
class DeviceSyncRepository(private val dynamoDBMapper: DynamoDBMapper) {
    
    companion object {
        private const val TAG = "DeviceSyncRepository"
    }
    
    /**
     * Register or update a device
     */
    suspend fun registerDevice(deviceSync: DeviceSync): Boolean = withContext(Dispatchers.IO) {
        try {
            if (!deviceSync.isValid()) {
                Log.w(TAG, "Invalid device sync data: $deviceSync")
                return@withContext false
            }
            
            // Update registration time if this is a new device
            val existingDevice = getDevice(deviceSync.userId, deviceSync.deviceId)
            if (existingDevice == null) {
                deviceSync.registrationTime = System.currentTimeMillis()
                Log.d(TAG, "Registering new device: ${deviceSync.deviceId} for user: ${deviceSync.userId}")
            } else {
                // Preserve registration time for existing device
                deviceSync.registrationTime = existingDevice.registrationTime
                Log.d(TAG, "Updating existing device: ${deviceSync.deviceId} for user: ${deviceSync.userId}")
            }
            
            deviceSync.updateActivity()
            dynamoDBMapper.save(deviceSync)
            Log.d(TAG, "Successfully registered/updated device: ${deviceSync.deviceId}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register device: ${deviceSync.deviceId}", e)
            false
        }
    }
    
    /**
     * Get a specific device
     */
    suspend fun getDevice(userId: String, deviceId: String): DeviceSync? = withContext(Dispatchers.IO) {
        try {
            val device = dynamoDBMapper.load(DeviceSync::class.java, userId, deviceId)
            if (device != null) {
                Log.d(TAG, "Successfully loaded device: $deviceId for user: $userId")
            } else {
                Log.d(TAG, "Device not found: $deviceId for user: $userId")
            }
            device
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get device: $deviceId for user: $userId", e)
            null
        }
    }
    
    /**
     * Get all devices for a user
     */
    suspend fun getUserDevices(userId: String): List<DeviceSync> = withContext(Dispatchers.IO) {
        try {
            val deviceSync = DeviceSync()
            deviceSync.userId = userId
            
            val queryExpression = DynamoDBQueryExpression<DeviceSync>()
                .withHashKeyValues(deviceSync)
                .withConsistentRead(false)
            
            val devices = dynamoDBMapper.query(DeviceSync::class.java, queryExpression)
            Log.d(TAG, "Successfully loaded ${devices.size} devices for user: $userId")
            devices
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get devices for user: $userId", e)
            emptyList()
        }
    }
    
    /**
     * Update device activity
     */
    suspend fun updateDeviceActivity(userId: String, deviceId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val device = getDevice(userId, deviceId)
            if (device != null) {
                device.updateActivity()
                dynamoDBMapper.save(device)
                Log.d(TAG, "Updated activity for device: $deviceId")
                true
            } else {
                Log.w(TAG, "Device not found for activity update: $deviceId")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update device activity: $deviceId", e)
            false
        }
    }
    
    /**
     * Mark sync as started
     */
    suspend fun markSyncStarted(userId: String, deviceId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val device = getDevice(userId, deviceId)
            if (device != null) {
                device.markSyncStarted()
                dynamoDBMapper.save(device)
                Log.d(TAG, "Marked sync started for device: $deviceId")
                true
            } else {
                Log.w(TAG, "Device not found for sync start: $deviceId")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to mark sync started for device: $deviceId", e)
            false
        }
    }
    
    /**
     * Mark sync as successful
     */
    suspend fun markSyncSuccess(userId: String, deviceId: String, profilesCount: Int): Boolean = withContext(Dispatchers.IO) {
        try {
            val device = getDevice(userId, deviceId)
            if (device != null) {
                device.markSyncSuccess(profilesCount)
                dynamoDBMapper.save(device)
                Log.d(TAG, "Marked sync success for device: $deviceId with $profilesCount profiles")
                true
            } else {
                Log.w(TAG, "Device not found for sync success: $deviceId")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to mark sync success for device: $deviceId", e)
            false
        }
    }
    
    /**
     * Mark sync as failed
     */
    suspend fun markSyncError(userId: String, deviceId: String, errorMessage: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val device = getDevice(userId, deviceId)
            if (device != null) {
                device.markSyncError(errorMessage)
                dynamoDBMapper.save(device)
                Log.d(TAG, "Marked sync error for device: $deviceId - $errorMessage")
                true
            } else {
                Log.w(TAG, "Device not found for sync error: $deviceId")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to mark sync error for device: $deviceId", e)
            false
        }
    }
    
    /**
     * Enable or disable sync for a device
     */
    suspend fun setSyncEnabled(userId: String, deviceId: String, enabled: Boolean): Boolean = withContext(Dispatchers.IO) {
        try {
            val device = getDevice(userId, deviceId)
            if (device != null) {
                device.syncEnabled = enabled
                if (enabled) {
                    device.resetErrors()
                } else {
                    device.syncStatus = DeviceSync.SYNC_STATUS_DISABLED
                }
                dynamoDBMapper.save(device)
                Log.d(TAG, "Set sync enabled=$enabled for device: $deviceId")
                true
            } else {
                Log.w(TAG, "Device not found for sync enable/disable: $deviceId")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set sync enabled for device: $deviceId", e)
            false
        }
    }
    
    /**
     * Reset sync errors for a device
     */
    suspend fun resetSyncErrors(userId: String, deviceId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val device = getDevice(userId, deviceId)
            if (device != null) {
                device.resetErrors()
                dynamoDBMapper.save(device)
                Log.d(TAG, "Reset sync errors for device: $deviceId")
                true
            } else {
                Log.w(TAG, "Device not found for error reset: $deviceId")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reset sync errors for device: $deviceId", e)
            false
        }
    }
    
    /**
     * Delete a device
     */
    suspend fun deleteDevice(userId: String, deviceId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val device = DeviceSync()
            device.userId = userId
            device.deviceId = deviceId
            
            dynamoDBMapper.delete(device)
            Log.d(TAG, "Successfully deleted device: $deviceId for user: $userId")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete device: $deviceId for user: $userId", e)
            false
        }
    }
    
    /**
     * Get active devices (recently active)
     */
    suspend fun getActiveDevices(userId: String): List<DeviceSync> = withContext(Dispatchers.IO) {
        try {
            val allDevices = getUserDevices(userId)
            val activeDevices = allDevices.filter { it.isActiveDevice() }
            
            Log.d(TAG, "Found ${activeDevices.size} active devices out of ${allDevices.size} total for user: $userId")
            activeDevices
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get active devices for user: $userId", e)
            emptyList()
        }
    }
    
    /**
     * Get devices that need sync
     */
    suspend fun getDevicesNeedingSync(userId: String): List<DeviceSync> = withContext(Dispatchers.IO) {
        try {
            val allDevices = getUserDevices(userId)
            val devicesNeedingSync = allDevices.filter { device ->
                device.needsSync(device.getRecommendedSyncInterval())
            }
            
            Log.d(TAG, "Found ${devicesNeedingSync.size} devices needing sync for user: $userId")
            devicesNeedingSync
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get devices needing sync for user: $userId", e)
            emptyList()
        }
    }
    
    /**
     * Get sync statistics for all user devices
     */
    suspend fun getSyncStats(userId: String): Map<String, Any> = withContext(Dispatchers.IO) {
        try {
            val devices = getUserDevices(userId)
            
            val stats = mutableMapOf<String, Any>()
            stats["total_devices"] = devices.size
            stats["active_devices"] = devices.count { it.isActiveDevice() }
            stats["sync_enabled_devices"] = devices.count { it.syncEnabled }
            stats["devices_with_errors"] = devices.count { it.syncErrors > 0 }
            
            if (devices.isNotEmpty()) {
                val healthScores = devices.map { it.getSyncHealthScore() }
                stats["avg_health_score"] = healthScores.average()
                stats["min_health_score"] = healthScores.minOrNull() ?: 0
                stats["max_health_score"] = healthScores.maxOrNull() ?: 0
                
                val lastSyncTimes = devices.mapNotNull { device ->
                    if (device.lastSuccessfulSync > 0) device.lastSuccessfulSync else null
                }
                if (lastSyncTimes.isNotEmpty()) {
                    stats["last_successful_sync"] = lastSyncTimes.maxOrNull() ?: 0L
                    stats["oldest_sync"] = lastSyncTimes.minOrNull() ?: 0L
                }
                
                // Count devices by sync status
                val statusCounts = devices.groupingBy { it.syncStatus }.eachCount()
                stats["sync_status_counts"] = statusCounts
            }
            
            Log.d(TAG, "Generated sync stats for user: $userId - $stats")
            stats
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get sync stats for user: $userId", e)
            emptyMap()
        }
    }
    
    /**
     * Clean up inactive devices (older than specified days)
     */
    suspend fun cleanupInactiveDevices(userId: String, inactiveDays: Int = 30): Int = withContext(Dispatchers.IO) {
        try {
            val cutoffTime = System.currentTimeMillis() - (inactiveDays * 24 * 60 * 60 * 1000L)
            val devices = getUserDevices(userId)
            
            val inactiveDevices = devices.filter { device ->
                device.lastActiveTime < cutoffTime && !device.syncEnabled
            }
            
            var deletedCount = 0
            for (device in inactiveDevices) {
                if (deleteDevice(userId, device.deviceId)) {
                    deletedCount++
                }
            }
            
            Log.d(TAG, "Cleaned up $deletedCount inactive devices for user: $userId")
            deletedCount
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cleanup inactive devices for user: $userId", e)
            0
        }
    }
    
    /**
     * Get device sync health summary
     */
    suspend fun getDeviceHealthSummary(userId: String, deviceId: String): Map<String, Any> = withContext(Dispatchers.IO) {
        try {
            val device = getDevice(userId, deviceId)
            if (device == null) {
                return@withContext emptyMap<String, Any>()
            }
            
            val summary = mutableMapOf<String, Any>()
            summary["device_name"] = device.getDisplayName()
            summary["sync_enabled"] = device.syncEnabled
            summary["sync_status"] = device.syncStatus
            summary["sync_status_description"] = device.getSyncStatusDescription()
            summary["health_score"] = device.getSyncHealthScore()
            summary["profiles_synced"] = device.profilesSynced
            summary["sync_errors"] = device.syncErrors
            summary["last_error"] = device.lastErrorMessage
            summary["is_active"] = device.isActiveDevice()
            summary["registration_time"] = device.registrationTime
            summary["last_sync_attempt"] = device.lastSyncAttempt
            summary["last_successful_sync"] = device.lastSuccessfulSync
            summary["recommended_sync_interval"] = device.getRecommendedSyncInterval()
            summary["needs_sync"] = device.needsSync()
            
            Log.d(TAG, "Generated health summary for device: $deviceId")
            summary
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get health summary for device: $deviceId", e)
            emptyMap()
        }
    }
}