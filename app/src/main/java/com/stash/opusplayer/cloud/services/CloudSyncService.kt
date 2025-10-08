package com.stash.opusplayer.cloud.services

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.preference.PreferenceManager
import com.stash.opusplayer.audio.settings.EnhancedAudioSettings
import com.stash.opusplayer.cloud.AWSConfig
import com.stash.opusplayer.cloud.CloudSyncErrorHandler
import com.stash.opusplayer.cloud.models.DeviceSync
import com.stash.opusplayer.cloud.models.UserAudioProfile
import com.stash.opusplayer.cloud.repositories.AudioProfileRepository
import com.stash.opusplayer.cloud.repositories.DeviceSyncRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.util.UUID

/**
 * Service for synchronizing audio settings with AWS DynamoDB
 * 
 * Provides offline-first architecture with automatic cloud sync
 */
class CloudSyncService private constructor(private val context: Context) {
    
    companion object {
        private const val TAG = "CloudSyncService"
        private const val PREFS_SYNC_CONFIG = "cloud_sync_config"
        private const val PREF_SYNC_ENABLED = "sync_enabled"
        private const val PREF_AUTO_SYNC_ENABLED = "auto_sync_enabled"
        private const val PREF_LAST_SYNC_TIME = "last_sync_time"
        private const val PREF_SESSION_ID = "current_session_id"
        
        @Volatile
        private var INSTANCE: CloudSyncService? = null
        
        fun getInstance(context: Context): CloudSyncService {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: CloudSyncService(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
    
    private val awsConfig = AWSConfig.getInstance(context)
    private val enhancedAudioSettings = EnhancedAudioSettings(context)
    private val syncPrefs = context.getSharedPreferences(PREFS_SYNC_CONFIG, Context.MODE_PRIVATE)
    private val errorHandler = CloudSyncErrorHandler(context)
    
    private var audioProfileRepository: AudioProfileRepository? = null
    private var deviceSyncRepository: DeviceSyncRepository? = null
    
    // Sync status tracking
    private val _syncStatus = MutableStateFlow(SyncStatus.IDLE)
    val syncStatus: StateFlow<SyncStatus> = _syncStatus.asStateFlow()
    
    private val _lastSyncTime = MutableStateFlow(getLastSyncTime())
    val lastSyncTime: StateFlow<Long> = _lastSyncTime.asStateFlow()
    
    private var currentSessionId = generateSessionId()
    
    enum class SyncStatus {
        IDLE, INITIALIZING, SYNCING, SUCCESS, ERROR, OFFLINE
    }
    
    data class SyncResult(
        val success: Boolean,
        val profilesSynced: Int = 0,
        val errorMessage: String = "",
        val timestamp: Long = System.currentTimeMillis()
    )
    
    /**
     * Initialize the cloud sync service
     */
    suspend fun initialize(): Boolean = withContext(Dispatchers.IO) {
        try {
            _syncStatus.value = SyncStatus.INITIALIZING
            Log.d(TAG, "Initializing cloud sync service...")
            
            // Initialize AWS configuration
            if (!awsConfig.initialize()) {
                Log.w(TAG, "Failed to initialize AWS configuration")
                _syncStatus.value = SyncStatus.OFFLINE
                return@withContext false
            }
            
            // Initialize repositories
            val dynamoDBMapper = awsConfig.getDynamoDBMapper()
            if (dynamoDBMapper != null) {
                audioProfileRepository = AudioProfileRepository(dynamoDBMapper)
                deviceSyncRepository = DeviceSyncRepository(dynamoDBMapper)
                
                // Register this device
                registerDevice()
                
                _syncStatus.value = SyncStatus.IDLE
                Log.d(TAG, "Cloud sync service initialized successfully")
                return@withContext true
            } else {
                Log.e(TAG, "Failed to get DynamoDB mapper")
                _syncStatus.value = SyncStatus.ERROR
                return@withContext false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize cloud sync service", e)
            _syncStatus.value = SyncStatus.ERROR
            false
        }
    }
    
    /**
     * Check if sync is enabled
     */
    fun isSyncEnabled(): Boolean {
        return syncPrefs.getBoolean(PREF_SYNC_ENABLED, false) && awsConfig.isInitialized()
    }
    
    /**
     * Enable or disable sync
     */
    suspend fun setSyncEnabled(enabled: Boolean): Boolean = withContext(Dispatchers.IO) {
        try {
            syncPrefs.edit().putBoolean(PREF_SYNC_ENABLED, enabled).apply()
            
            if (enabled) {
                // Initialize if not already done
                if (!awsConfig.isInitialized()) {
                    initialize()
                }
                
                // Perform initial sync
                syncAll()
            } else {
                // Update device sync status
                deviceSyncRepository?.setSyncEnabled(awsConfig.getUserId(), awsConfig.getDeviceId(), false)
            }
            
            Log.d(TAG, "Sync enabled set to: $enabled")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set sync enabled: $enabled", e)
            false
        }
    }
    
    /**
     * Perform full sync of all audio profiles
     */
    suspend fun syncAll(): SyncResult = withContext(Dispatchers.IO) {
        if (!isSyncEnabled()) {
            return@withContext SyncResult(false, errorMessage = "Sync is disabled")
        }
        
        val startTime = System.currentTimeMillis()
        var retryCount = 0
        
        try {
            val syncResult = performSyncOperation()
            val duration = System.currentTimeMillis() - startTime
            errorHandler.logSyncMetrics("syncAll", true, duration, retryCount)
            return@withContext syncResult
        } catch (e: Exception) {
            val duration = System.currentTimeMillis() - startTime
            val error = errorHandler.categorizeError(e)
            
            Log.e(TAG, "Failed to perform full sync", e)
            errorHandler.logSyncMetrics("syncAll", false, duration, retryCount, error)
            
            deviceSyncRepository?.markSyncError(awsConfig.getUserId(), awsConfig.getDeviceId(), error.message)
            _syncStatus.value = SyncStatus.ERROR
            
            // Handle specific error scenarios
            if (errorHandler.shouldRefreshCredentials(error)) {
                awsConfig.refreshCredentials()
            }
            if (errorHandler.shouldDisableAutoSync(error)) {
                syncPrefs.edit().putBoolean(PREF_AUTO_SYNC_ENABLED, false).apply()
                Log.w(TAG, "Auto-sync disabled due to persistent error: ${error.category}")
            }
            
            return@withContext SyncResult(false, errorMessage = errorHandler.createUserMessage(error, "Sync"))
        }
    }
    
    /**
     * Perform the actual sync operation (non-suspend)
     */
    private suspend fun performSyncOperation(): SyncResult {
        _syncStatus.value = SyncStatus.SYNCING
        deviceSyncRepository?.markSyncStarted(awsConfig.getUserId(), awsConfig.getDeviceId())
        
        Log.d(TAG, "Starting full sync...")
        
        val userId = awsConfig.getUserId()
        var syncedCount = 0
        
        // Sync default profile
        val defaultProfile = createProfileFromLocalSettings(userId, UserAudioProfile.DEFAULT_PROFILE_ID, "Default Profile", true)
        if (syncProfile(defaultProfile)) {
            syncedCount++
        }
        
        // Sync other predefined profiles if they have been customized
        // (This could be extended to sync all custom profiles)
        
        val result = SyncResult(true, syncedCount)
        
        // Update sync timestamps
        updateLastSyncTime()
        deviceSyncRepository?.markSyncSuccess(userId, awsConfig.getDeviceId(), syncedCount)
        
        _syncStatus.value = SyncStatus.SUCCESS
        Log.d(TAG, "Full sync completed successfully - $syncedCount profiles synced")
        
        return result
    }
    
    /**
     * Sync a specific audio profile
     */
    suspend fun syncProfile(profile: UserAudioProfile): Boolean = withContext(Dispatchers.IO) {
        if (!isSyncEnabled() || audioProfileRepository == null) {
            return@withContext false
        }
        
        try {
            val repository = audioProfileRepository!!
            
            // Get cloud version
            val cloudProfile = repository.getProfile(profile.userId, profile.profileId)
            
            // Sync with conflict resolution
            val resolvedProfile = repository.syncProfile(profile, cloudProfile)
            
            if (resolvedProfile != null) {
                // Apply resolved profile to local settings if cloud version is newer
                if (resolvedProfile != profile) {
                    applyProfileToLocalSettings(resolvedProfile)
                }
                Log.d(TAG, "Successfully synced profile: ${profile.profileId}")
                true
            } else {
                Log.w(TAG, "Failed to sync profile: ${profile.profileId}")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sync profile: ${profile.profileId}", e)
            false
        }
    }
    
    /**
     * Download profile from cloud and apply to local settings
     */
    suspend fun downloadProfile(profileId: String): Boolean = withContext(Dispatchers.IO) {
        if (!isSyncEnabled() || audioProfileRepository == null) {
            return@withContext false
        }
        
        try {
            val repository = audioProfileRepository!!
            val userId = awsConfig.getUserId()
            
            val cloudProfile = repository.getProfile(userId, profileId)
            if (cloudProfile != null) {
                applyProfileToLocalSettings(cloudProfile)
                Log.d(TAG, "Successfully downloaded and applied profile: $profileId")
                true
            } else {
                Log.w(TAG, "Profile not found in cloud: $profileId")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to download profile: $profileId", e)
            false
        }
    }
    
    /**
     * Upload current local settings as a profile
     */
    suspend fun uploadCurrentSettings(profileId: String, profileName: String): Boolean = withContext(Dispatchers.IO) {
        if (!isSyncEnabled() || audioProfileRepository == null) {
            return@withContext false
        }
        
        try {
            val userId = awsConfig.getUserId()
            val profile = createProfileFromLocalSettings(userId, profileId, profileName, false)
            
            val repository = audioProfileRepository!!
            val success = repository.saveProfile(profile)
            
            if (success) {
                Log.d(TAG, "Successfully uploaded current settings as profile: $profileId")
            } else {
                Log.w(TAG, "Failed to upload current settings as profile: $profileId")
            }
            
            success
        } catch (e: Exception) {
            Log.e(TAG, "Failed to upload current settings as profile: $profileId", e)
            false
        }
    }
    
    /**
     * Create a UserAudioProfile from current local settings
     */
    private fun createProfileFromLocalSettings(userId: String, profileId: String, profileName: String, isDefault: Boolean): UserAudioProfile {
        val profile = UserAudioProfile(
            userId = userId,
            profileId = profileId,
            profileName = profileName,
            deviceId = awsConfig.getDeviceId(),
            isDefault = isDefault,
            version = "11.1.0"
        )
        
        // Gather all audio settings
        val audioSettings = mutableMapOf<String, Any>()
        
        // Professional audio processor settings
        audioSettings["professional_processor_enabled"] = enhancedAudioSettings.isProfessionalProcessorEnabled()
        audioSettings["compression_enabled"] = enhancedAudioSettings.isCompressionEnabled()
        audioSettings["compression_threshold"] = enhancedAudioSettings.getCompressionThreshold()
        audioSettings["compression_ratio"] = enhancedAudioSettings.getCompressionRatio()
        audioSettings["compression_attack"] = enhancedAudioSettings.getCompressionAttack()
        audioSettings["compression_release"] = enhancedAudioSettings.getCompressionRelease()
        audioSettings["stereo_width"] = enhancedAudioSettings.getStereoWidth()
        audioSettings["auto_gain_enabled"] = enhancedAudioSettings.isAutoGainEnabled()
        audioSettings["target_lufs"] = enhancedAudioSettings.getTargetLufs()
        audioSettings["crossfeed_enabled"] = enhancedAudioSettings.isCrossfeedEnabled()
        audioSettings["tube_warmth"] = enhancedAudioSettings.getTubeWarmth()
        audioSettings["current_audio_profile"] = enhancedAudioSettings.getCurrentAudioProfile()
        
        // Spectrum analyzer settings
        audioSettings["spectrum_analyzer_enabled"] = enhancedAudioSettings.isSpectrumAnalyzerEnabled()
        audioSettings["spectrum_sensitivity"] = enhancedAudioSettings.getSpectrumSensitivity()
        audioSettings["spectrum_smoothing"] = enhancedAudioSettings.getSpectrumSmoothing()
        
        // Enhanced equalizer settings
        audioSettings["enhanced_eq_enabled"] = enhancedAudioSettings.isEnhancedEqualizerEnabled()
        audioSettings["enhanced_eq_preset"] = enhancedAudioSettings.getEnhancedEqualizerPreset()
        audioSettings["enhanced_band_levels"] = enhancedAudioSettings.getEnhancedBandLevels()
        
        profile.setAudioSettings(audioSettings)
        return profile
    }
    
    /**
     * Apply a profile's settings to local SharedPreferences
     */
    private fun applyProfileToLocalSettings(profile: UserAudioProfile) {
        val settings = profile.getAudioSettings()
        
        // Professional audio processor settings
        settings["professional_processor_enabled"]?.let { 
            enhancedAudioSettings.setProfessionalProcessorEnabled(it as Boolean) 
        }
        settings["compression_enabled"]?.let { 
            enhancedAudioSettings.setCompressionEnabled(it as Boolean) 
        }
        settings["compression_threshold"]?.let { 
            enhancedAudioSettings.setCompressionThreshold(it as Float) 
        }
        settings["compression_ratio"]?.let { 
            enhancedAudioSettings.setCompressionRatio(it as Float) 
        }
        settings["compression_attack"]?.let { 
            enhancedAudioSettings.setCompressionAttack(it as Float) 
        }
        settings["compression_release"]?.let { 
            enhancedAudioSettings.setCompressionRelease(it as Float) 
        }
        settings["stereo_width"]?.let { 
            enhancedAudioSettings.setStereoWidth(it as Float) 
        }
        settings["auto_gain_enabled"]?.let { 
            enhancedAudioSettings.setAutoGainEnabled(it as Boolean) 
        }
        settings["target_lufs"]?.let { 
            enhancedAudioSettings.setTargetLufs(it as Float) 
        }
        settings["crossfeed_enabled"]?.let { 
            enhancedAudioSettings.setCrossfeedEnabled(it as Boolean) 
        }
        settings["tube_warmth"]?.let { 
            enhancedAudioSettings.setTubeWarmth(it as Float) 
        }
        settings["current_audio_profile"]?.let { 
            enhancedAudioSettings.setCurrentAudioProfile(it as String) 
        }
        
        // Spectrum analyzer settings
        settings["spectrum_analyzer_enabled"]?.let { 
            enhancedAudioSettings.setSpectrumAnalyzerEnabled(it as Boolean) 
        }
        settings["spectrum_sensitivity"]?.let { 
            enhancedAudioSettings.setSpectrumSensitivity(it as Float) 
        }
        settings["spectrum_smoothing"]?.let { 
            enhancedAudioSettings.setSpectrumSmoothing(it as Float) 
        }
        
        // Enhanced equalizer settings
        settings["enhanced_eq_enabled"]?.let { 
            enhancedAudioSettings.setEnhancedEqualizerEnabled(it as Boolean) 
        }
        settings["enhanced_eq_preset"]?.let { 
            enhancedAudioSettings.setEnhancedEqualizerPreset(it as String) 
        }
        settings["enhanced_band_levels"]?.let { 
            enhancedAudioSettings.setEnhancedBandLevels(it as String) 
        }
        
        Log.d(TAG, "Applied profile settings to local preferences: ${profile.profileId}")
    }
    
    /**
     * Register this device with the sync service
     */
    private suspend fun registerDevice() {
        if (deviceSyncRepository == null) return
        
        try {
            val deviceSync = DeviceSync(
                userId = awsConfig.getUserId(),
                deviceId = awsConfig.getDeviceId(),
                deviceName = "${Build.MANUFACTURER} ${Build.MODEL}",
                deviceModel = Build.MODEL,
                androidVersion = Build.VERSION.RELEASE,
                appVersion = "11.1.0"
            )
            
            deviceSyncRepository!!.registerDevice(deviceSync)
            Log.d(TAG, "Device registered successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register device", e)
        }
    }
    
    /**
     * Get sync status information
     */
    suspend fun getSyncInfo(): Map<String, Any> = withContext(Dispatchers.IO) {
        val info = mutableMapOf<String, Any>()
        
        info["sync_enabled"] = isSyncEnabled()
        info["aws_initialized"] = awsConfig.isInitialized()
        info["sync_status"] = _syncStatus.value.name
        info["last_sync_time"] = getLastSyncTime()
        info["device_id"] = awsConfig.getDeviceId()
        info["user_id"] = awsConfig.getUserId()
        info["session_id"] = currentSessionId
        
        // Device sync info
        deviceSyncRepository?.let { repo ->
            try {
                val deviceHealth = repo.getDeviceHealthSummary(awsConfig.getUserId(), awsConfig.getDeviceId())
                info["device_health"] = deviceHealth
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get device health info", e)
            }
        }
        
        info
    }
    
    /**
     * Generate a new session ID
     */
    private fun generateSessionId(): String {
        val sessionId = UUID.randomUUID().toString()
        syncPrefs.edit().putString(PREF_SESSION_ID, sessionId).apply()
        return sessionId
    }
    
    /**
     * Get current session ID
     */
    fun getSessionId(): String {
        if (currentSessionId.isEmpty()) {
            currentSessionId = syncPrefs.getString(PREF_SESSION_ID, null) ?: generateSessionId()
        }
        return currentSessionId
    }
    
    /**
     * Update last sync time
     */
    private fun updateLastSyncTime() {
        val now = System.currentTimeMillis()
        syncPrefs.edit().putLong(PREF_LAST_SYNC_TIME, now).apply()
        _lastSyncTime.value = now
    }
    
    /**
     * Get last sync time
     */
    private fun getLastSyncTime(): Long {
        return syncPrefs.getLong(PREF_LAST_SYNC_TIME, 0)
    }
    
    /**
     * Check if automatic sync should run
     */
    fun shouldAutoSync(): Boolean {
        if (!isSyncEnabled()) return false
        
        val autoSyncEnabled = syncPrefs.getBoolean(PREF_AUTO_SYNC_ENABLED, true)
        if (!autoSyncEnabled) return false
        
        val lastSync = getLastSyncTime()
        val timeSinceLastSync = System.currentTimeMillis() - lastSync
        
        // Auto sync every 30 minutes
        return timeSinceLastSync > (30 * 60 * 1000)
    }
    
    /**
     * Clean up resources
     */
    fun cleanup() {
        awsConfig.cleanup()
        Log.d(TAG, "Cloud sync service cleaned up")
    }
}