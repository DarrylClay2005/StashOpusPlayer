package com.stash.opusplayer.utils

import android.content.Context
import android.util.Log
import java.io.File

/**
 * Manages YouTube API key storage in a dedicated folder on the device.
 * Replaces SharedPreferences storage for better organization and security.
 */
object YouTubeApiKeyManager {
    private const val TAG = "YouTubeApiKeyManager"
    private const val API_KEY_FOLDER = "youtube_api"
    private const val API_KEY_FILE = "api_key.txt"
    private const val CUSTOM_PATH_PREF = "custom_youtube_api_path"
    
    /**
     * Get the dedicated folder for YouTube API key storage
     */
    private fun getApiKeyFolder(context: Context): File {
        // Check for custom path first
        val prefs = context.getSharedPreferences("storage_settings", Context.MODE_PRIVATE)
        val customPath = prefs.getString(CUSTOM_PATH_PREF, null)
        
        val folder = if (customPath != null && File(customPath).exists()) {
            File(customPath)
        } else {
            File(context.filesDir, API_KEY_FOLDER)
        }
        
        if (!folder.exists()) {
            folder.mkdirs()
        }
        return folder
    }
    
    /**
     * Get the API key file
     */
    private fun getApiKeyFile(context: Context): File {
        return File(getApiKeyFolder(context), API_KEY_FILE)
    }
    
    /**
     * Save YouTube API key to dedicated folder
     */
    fun saveApiKey(context: Context, apiKey: String): Boolean {
        return try {
            val trimmedKey = apiKey.trim()
            if (trimmedKey.isBlank()) {
                Log.e(TAG, "Cannot save blank API key")
                return false
            }
            // Save locally (cache)
            val folder = getApiKeyFolder(context)
            if (!folder.exists()) folder.mkdirs()
            val file = File(folder, API_KEY_FILE)
            file.writeText(trimmedKey)
            // Try push to cloud (best-effort)
            runCatching {
                val uid = com.amplifyframework.core.Amplify.Auth.currentUser.userId
                val key = "users/${uid}/secrets/youtube_api_key.txt"
                val tmp = File.createTempFile("ytkey_", ".txt", context.cacheDir)
                tmp.writeText(trimmedKey)
                com.amplifyframework.core.Amplify.Storage.uploadFile(key, tmp, { _ -> tmp.delete() }, { _ -> tmp.delete() })
            }
            Log.d(TAG, "YouTube API key saved (local + cloud if signed in)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save YouTube API key: ${e.message}", e)
            false
        }
    }
    
    /**
     * Load YouTube API key from dedicated folder
     */
    fun loadApiKey(context: Context): String? {
        // Try cloud first (cached to local)
        try {
            val uid = com.amplifyframework.core.Amplify.Auth.currentUser.userId
            val key = "users/${uid}/secrets/youtube_api_key.txt"
            val tmp = File.createTempFile("ytkey_dl_", ".txt", context.cacheDir)
            val latch = java.util.concurrent.CountDownLatch(1)
            var downloaded = false
            com.amplifyframework.core.Amplify.Storage.downloadFile(key, tmp, { _ -> downloaded = true; latch.countDown() }, { _ -> latch.countDown() })
            latch.await(400, java.util.concurrent.TimeUnit.MILLISECONDS)
            if (downloaded) {
                val text = tmp.readText().trim()
                if (text.isNotBlank()) {
                    // Write to cache file
                    runCatching { getApiKeyFile(context).writeText(text) }
                    return text
                }
            }
        } catch (_: Exception) { /* no cloud key */ }
        // Fallback to local
        return try {
            val file = getApiKeyFile(context)
            if (file.exists() && file.canRead()) {
                val key = file.readText().trim()
                if (key.isNotBlank()) {
                    Log.d(TAG, "YouTube API key loaded successfully")
                    key
                } else null
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load YouTube API key", e)
            null
        }
    }
    
    /**
     * Check if API key exists
     */
    fun hasApiKey(context: Context): Boolean {
        val file = getApiKeyFile(context)
        return file.exists() && file.length() > 0
    }
    
    /**
     * Delete YouTube API key
     */
    fun deleteApiKey(context: Context): Boolean {
        return try {
            val file = getApiKeyFile(context)
            if (file.exists()) {
                file.delete()
                Log.d(TAG, "YouTube API key deleted")
                true
            } else {
                Log.d(TAG, "YouTube API key file does not exist, nothing to delete")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete YouTube API key", e)
            false
        }
    }
    
    /**
     * Migrate from SharedPreferences to file storage (for backward compatibility)
     */
    fun migrateFromSharedPreferences(context: Context): Boolean {
        return try {
            val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
            val oldKey = prefs.getString("user_youtube_api_key", null)
            
            if (!oldKey.isNullOrBlank() && !hasApiKey(context)) {
                // Migrate old key to new storage
                if (saveApiKey(context, oldKey)) {
                    // Remove from SharedPreferences after successful migration
                    prefs.edit().remove("user_youtube_api_key").apply()
                    Log.d(TAG, "Migrated YouTube API key from SharedPreferences to file storage")
                    true
                } else {
                    false
                }
            } else {
                // No migration needed
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to migrate YouTube API key", e)
            false
        }
    }
    
    /**
     * Get the folder path for display purposes
     */
    fun getApiKeyFolderPath(context: Context): String {
        return getApiKeyFolder(context).absolutePath
    }
    
    /**
     * Set custom path for YouTube API key storage
     */
    fun setCustomApiKeyPath(context: Context, path: String): Boolean {
        return try {
            val folder = File(path)
            if (!folder.exists()) {
                folder.mkdirs()
            }
            
            if (folder.exists() && folder.isDirectory) {
                val prefs = context.getSharedPreferences("storage_settings", Context.MODE_PRIVATE)
                prefs.edit().putString(CUSTOM_PATH_PREF, path).apply()
                Log.d(TAG, "Custom API key path set to: $path")
                true
            } else {
                Log.e(TAG, "Failed to create custom path: $path")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set custom API key path", e)
            false
        }
    }
    
    /**
     * Auto-detect YouTube API key from common locations
     */
    fun autoDetectApiKey(context: Context): String? {
        val commonLocations = listOf(
            File(context.filesDir, API_KEY_FOLDER),
            File(context.externalCacheDir, API_KEY_FOLDER),
            File(context.getExternalFilesDir(null), API_KEY_FOLDER),
            File(context.cacheDir, API_KEY_FOLDER),
            // Check Downloads folder
            File(android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOWNLOADS), "youtube_api")
        )
        
        for (location in commonLocations) {
            val apiKeyFile = File(location, API_KEY_FILE)
            if (apiKeyFile.exists() && apiKeyFile.canRead()) {
                try {
                    val key = apiKeyFile.readText().trim()
                    if (key.isNotBlank()) {
                        Log.d(TAG, "Auto-detected API key at: ${apiKeyFile.absolutePath}")
                        // Save the detected location as custom path
                        setCustomApiKeyPath(context, location.absolutePath)
                        return key
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to read API key from ${apiKeyFile.absolutePath}", e)
                }
            }
        }
        
        Log.d(TAG, "No API key found in common locations")
        return null
    }
}
