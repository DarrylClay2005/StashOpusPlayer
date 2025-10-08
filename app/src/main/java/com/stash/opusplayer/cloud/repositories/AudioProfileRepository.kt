package com.stash.opusplayer.cloud.repositories

import android.util.Log
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBMapper
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBQueryExpression
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBScanExpression
import com.amazonaws.services.dynamodbv2.model.AttributeValue
import com.stash.opusplayer.cloud.models.UserAudioProfile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Repository for managing user audio profiles in DynamoDB
 * 
 * Handles CRUD operations for audio settings synchronization
 */
class AudioProfileRepository(private val dynamoDBMapper: DynamoDBMapper) {
    
    companion object {
        private const val TAG = "AudioProfileRepository"
    }
    
    /**
     * Save or update an audio profile
     */
    suspend fun saveProfile(profile: UserAudioProfile): Boolean = withContext(Dispatchers.IO) {
        try {
            if (!profile.isValid()) {
                Log.w(TAG, "Invalid profile data: $profile")
                return@withContext false
            }
            
            profile.markModified()
            dynamoDBMapper.save(profile)
            Log.d(TAG, "Successfully saved profile: ${profile.profileId} for user: ${profile.userId}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save profile: ${profile.profileId}", e)
            false
        }
    }
    
    /**
     * Get a specific audio profile
     */
    suspend fun getProfile(userId: String, profileId: String): UserAudioProfile? = withContext(Dispatchers.IO) {
        try {
            val profile = dynamoDBMapper.load(UserAudioProfile::class.java, userId, profileId)
            if (profile != null) {
                Log.d(TAG, "Successfully loaded profile: $profileId for user: $userId")
            } else {
                Log.d(TAG, "Profile not found: $profileId for user: $userId")
            }
            profile
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get profile: $profileId for user: $userId", e)
            null
        }
    }
    
    /**
     * Get all audio profiles for a user
     */
    suspend fun getAllProfiles(userId: String): List<UserAudioProfile> = withContext(Dispatchers.IO) {
        try {
            val profile = UserAudioProfile()
            profile.userId = userId
            
            val queryExpression = DynamoDBQueryExpression<UserAudioProfile>()
                .withHashKeyValues(profile)
                .withConsistentRead(false)
            
            val profiles = dynamoDBMapper.query(UserAudioProfile::class.java, queryExpression)
            Log.d(TAG, "Successfully loaded ${profiles.size} profiles for user: $userId")
            profiles
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get all profiles for user: $userId", e)
            emptyList()
        }
    }
    
    /**
     * Get the default audio profile for a user
     */
    suspend fun getDefaultProfile(userId: String): UserAudioProfile? = withContext(Dispatchers.IO) {
        try {
            // First try to get explicit default profile
            val profiles = getAllProfiles(userId)
            val defaultProfile = profiles.find { it.isDefault }
            
            if (defaultProfile != null) {
                Log.d(TAG, "Found default profile: ${defaultProfile.profileId} for user: $userId")
                return@withContext defaultProfile
            }
            
            // If no explicit default, try to get "default" profile
            val fallbackProfile = getProfile(userId, UserAudioProfile.DEFAULT_PROFILE_ID)
            if (fallbackProfile != null) {
                Log.d(TAG, "Using fallback default profile for user: $userId")
                return@withContext fallbackProfile
            }
            
            Log.d(TAG, "No default profile found for user: $userId")
            null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get default profile for user: $userId", e)
            null
        }
    }
    
    /**
     * Delete an audio profile
     */
    suspend fun deleteProfile(userId: String, profileId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val profile = UserAudioProfile()
            profile.userId = userId
            profile.profileId = profileId
            
            dynamoDBMapper.delete(profile)
            Log.d(TAG, "Successfully deleted profile: $profileId for user: $userId")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete profile: $profileId for user: $userId", e)
            false
        }
    }
    
    /**
     * Set a profile as the default
     */
    suspend fun setDefaultProfile(userId: String, profileId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            // Get all profiles and update default flags
            val profiles = getAllProfiles(userId)
            
            var updated = false
            for (profile in profiles) {
                val wasDefault = profile.isDefault
                profile.isDefault = (profile.profileId == profileId)
                
                if (wasDefault != profile.isDefault) {
                    dynamoDBMapper.save(profile)
                    updated = true
                }
            }
            
            Log.d(TAG, "Successfully set default profile: $profileId for user: $userId")
            updated
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set default profile: $profileId for user: $userId", e)
            false
        }
    }
    
    /**
     * Sync profile with conflict resolution (last-write-wins)
     */
    suspend fun syncProfile(localProfile: UserAudioProfile, cloudProfile: UserAudioProfile?): UserAudioProfile? = withContext(Dispatchers.IO) {
        try {
            val resolvedProfile = when {
                cloudProfile == null -> {
                    // No cloud profile exists, upload local
                    Log.d(TAG, "No cloud profile, uploading local: ${localProfile.profileId}")
                    localProfile
                }
                localProfile.isNewerThan(cloudProfile) -> {
                    // Local is newer, upload local
                    Log.d(TAG, "Local profile is newer, uploading: ${localProfile.profileId}")
                    localProfile
                }
                else -> {
                    // Cloud is newer or same, use cloud
                    Log.d(TAG, "Cloud profile is newer or same, using cloud: ${cloudProfile.profileId}")
                    cloudProfile
                }
            }
            
            // Save the resolved profile to cloud
            if (saveProfile(resolvedProfile)) {
                resolvedProfile
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to sync profile: ${localProfile.profileId}", e)
            null
        }
    }
    
    /**
     * Batch save multiple profiles
     */
    suspend fun saveProfiles(profiles: List<UserAudioProfile>): Int = withContext(Dispatchers.IO) {
        var savedCount = 0
        
        try {
            for (profile in profiles) {
                if (saveProfile(profile)) {
                    savedCount++
                }
            }
            Log.d(TAG, "Successfully saved $savedCount/${profiles.size} profiles")
        } catch (e: Exception) {
            Log.e(TAG, "Error in batch save profiles", e)
        }
        
        savedCount
    }
    
    /**
     * Get profiles modified after a specific timestamp
     */
    suspend fun getProfilesModifiedAfter(userId: String, timestamp: Long): List<UserAudioProfile> = withContext(Dispatchers.IO) {
        try {
            val allProfiles = getAllProfiles(userId)
            val filteredProfiles = allProfiles.filter { it.lastModified > timestamp }
            
            Log.d(TAG, "Found ${filteredProfiles.size} profiles modified after $timestamp for user: $userId")
            filteredProfiles
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get profiles modified after $timestamp for user: $userId", e)
            emptyList()
        }
    }
    
    /**
     * Search profiles by name
     */
    suspend fun searchProfiles(userId: String, nameQuery: String): List<UserAudioProfile> = withContext(Dispatchers.IO) {
        try {
            val allProfiles = getAllProfiles(userId)
            val matchingProfiles = allProfiles.filter { 
                it.profileName.contains(nameQuery, ignoreCase = true) ||
                it.profileId.contains(nameQuery, ignoreCase = true)
            }
            
            Log.d(TAG, "Found ${matchingProfiles.size} profiles matching '$nameQuery' for user: $userId")
            matchingProfiles
        } catch (e: Exception) {
            Log.e(TAG, "Failed to search profiles for query: $nameQuery", e)
            emptyList()
        }
    }
    
    /**
     * Get profile statistics
     */
    suspend fun getProfileStats(userId: String): Map<String, Any> = withContext(Dispatchers.IO) {
        try {
            val profiles = getAllProfiles(userId)
            
            val stats = mutableMapOf<String, Any>()
            stats["total_profiles"] = profiles.size
            stats["default_profiles"] = profiles.count { it.isDefault }
            stats["sync_enabled_profiles"] = profiles.count { it.syncEnabled }
            
            if (profiles.isNotEmpty()) {
                stats["newest_profile_time"] = profiles.maxOfOrNull { it.lastModified } ?: 0L
                stats["oldest_profile_time"] = profiles.minOfOrNull { it.lastModified } ?: 0L
                
                val avgSettings = profiles.map { it.getAudioSettings().size }.average()
                stats["avg_settings_per_profile"] = avgSettings
            }
            
            Log.d(TAG, "Generated profile stats for user: $userId - $stats")
            stats
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get profile stats for user: $userId", e)
            emptyMap()
        }
    }
}