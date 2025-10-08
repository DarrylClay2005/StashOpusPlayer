package com.stash.opusplayer.cloud.models

import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBAttribute
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBHashKey
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBRangeKey
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBTable
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

/**
 * DynamoDB model for user audio profiles and settings
 * 
 * Table structure:
 * - userId (Hash Key): Unique user identifier
 * - profileId (Range Key): Profile identifier (e.g., "default", "mastering", "audiophile")
 * - Contains all audio settings as JSON blob for flexibility
 */
@DynamoDBTable(tableName = "StashOpusPlayer_UserAudioProfiles")
data class UserAudioProfile(
    
    @DynamoDBHashKey(attributeName = "userId")
    var userId: String = "",
    
    @DynamoDBRangeKey(attributeName = "profileId")
    var profileId: String = "",
    
    @DynamoDBAttribute(attributeName = "profileName")
    var profileName: String = "",
    
    @DynamoDBAttribute(attributeName = "audioSettings")
    var audioSettingsJson: String = "{}",
    
    @DynamoDBAttribute(attributeName = "deviceId")
    var deviceId: String = "",
    
    @DynamoDBAttribute(attributeName = "lastModified")
    var lastModified: Long = System.currentTimeMillis(),
    
    @DynamoDBAttribute(attributeName = "version")
    var version: String = "11.1.0",
    
    @DynamoDBAttribute(attributeName = "isDefault")
    var isDefault: Boolean = false,
    
    @DynamoDBAttribute(attributeName = "syncEnabled")
    var syncEnabled: Boolean = true
) {
    
    companion object {
        const val DEFAULT_PROFILE_ID = "default"
        const val MASTERING_PROFILE_ID = "mastering"
        const val AUDIOPHILE_PROFILE_ID = "audiophile"
        const val BROADCAST_PROFILE_ID = "broadcast"
        const val CLUB_PROFILE_ID = "club"
        const val VINTAGE_PROFILE_ID = "vintage"
        
        private val gson = Gson()
    }
    
    /**
     * Convert audio settings map to JSON string
     */
    fun setAudioSettings(settings: Map<String, Any>) {
        audioSettingsJson = gson.toJson(settings)
    }
    
    /**
     * Parse JSON string back to audio settings map
     */
    fun getAudioSettings(): Map<String, Any> {
        return try {
            val type = object : TypeToken<Map<String, Any>>() {}.type
            gson.fromJson(audioSettingsJson, type) ?: emptyMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }
    
    /**
     * Get specific audio setting value
     */
    @Suppress("UNCHECKED_CAST")
    fun <T> getAudioSetting(key: String, defaultValue: T): T {
        val settings = getAudioSettings()
        return settings[key] as? T ?: defaultValue
    }
    
    /**
     * Set specific audio setting value
     */
    fun setAudioSetting(key: String, value: Any) {
        val settings = getAudioSettings().toMutableMap()
        settings[key] = value
        setAudioSettings(settings)
    }
    
    /**
     * Create a copy for local modifications
     */
    fun copy(): UserAudioProfile {
        return UserAudioProfile(
            userId = userId,
            profileId = profileId,
            profileName = profileName,
            audioSettingsJson = audioSettingsJson,
            deviceId = deviceId,
            lastModified = lastModified,
            version = version,
            isDefault = isDefault,
            syncEnabled = syncEnabled
        )
    }
    
    /**
     * Check if this profile has been modified more recently than another
     */
    fun isNewerThan(other: UserAudioProfile?): Boolean {
        return other == null || this.lastModified > other.lastModified
    }
    
    /**
     * Mark profile as modified
     */
    fun markModified() {
        lastModified = System.currentTimeMillis()
    }
    
    /**
     * Validate profile data
     */
    fun isValid(): Boolean {
        return userId.isNotBlank() && 
               profileId.isNotBlank() && 
               profileName.isNotBlank()
    }
    
    /**
     * Get profile description for UI display
     */
    fun getDisplayDescription(): String {
        val settingsCount = getAudioSettings().size
        return "$profileName ($settingsCount settings) - Last modified: ${java.text.SimpleDateFormat("yyyy-MM-dd HH:mm", java.util.Locale.getDefault()).format(java.util.Date(lastModified))}"
    }
    
    override fun toString(): String {
        return "UserAudioProfile(userId='$userId', profileId='$profileId', profileName='$profileName', deviceId='$deviceId', lastModified=$lastModified, version='$version', isDefault=$isDefault, syncEnabled=$syncEnabled)"
    }
}