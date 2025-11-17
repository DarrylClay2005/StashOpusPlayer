package com.stash.opusplayer.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.stash.opusplayer.data.Song
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Manages metadata and artwork storage in a dedicated folder on the device.
 * This is the primary source for metadata extraction and artwork loading.
 */
object MetadataStorageManager {
    private const val TAG = "MetadataStorageManager"
    private const val METADATA_FOLDER = "metadata"
    private const val ARTWORK_SUBFOLDER = "artwork"
    private const val METADATA_SUBFOLDER = "info"
    private const val CUSTOM_PATH_PREF = "custom_metadata_path"
    
    /**
     * Get the dedicated metadata folder
     */
    private fun getMetadataFolder(context: Context): File {
        // Check for custom path first
        val prefs = context.getSharedPreferences("storage_settings", Context.MODE_PRIVATE)
        val customPath = prefs.getString(CUSTOM_PATH_PREF, null)
        
        val folder = if (customPath != null && File(customPath).exists()) {
            File(customPath)
        } else {
            File(context.filesDir, METADATA_FOLDER)
        }
        
        if (!folder.exists()) {
            folder.mkdirs()
        }
        return folder
    }
    
    /**
     * Get the artwork subfolder
     */
    private fun getArtworkFolder(context: Context): File {
        val folder = File(getMetadataFolder(context), ARTWORK_SUBFOLDER)
        if (!folder.exists()) {
            folder.mkdirs()
        }
        return folder
    }
    
    /**
     * Get the metadata info subfolder
     */
    private fun getMetadataInfoFolder(context: Context): File {
        val folder = File(getMetadataFolder(context), METADATA_SUBFOLDER)
        if (!folder.exists()) {
            folder.mkdirs()
        }
        return folder
    }
    
    /**
     * Generate a unique ID for a song based on path or video ID
     */
    private fun generateSongId(identifier: String): String {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(identifier.toByteArray())
            hash.joinToString("") { "%02x".format(it) }.take(16)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate song ID", e)
            identifier.replace(Regex("[^a-zA-Z0-9]"), "_").take(16)
        }
    }
    
    /**
     * Get artwork file for a song
     */
    private fun getArtworkFile(context: Context, identifier: String): File {
        val songId = generateSongId(identifier)
        return File(getArtworkFolder(context), "$songId.jpg")
    }

    // Public accessors for file-based artwork loading
    fun getArtworkFilePath(context: Context, identifier: String): String? {
        val f = getArtworkFile(context, identifier)
        return if (f.exists() && f.canRead()) f.absolutePath else null
    }

    fun getArtworkUri(context: Context, identifier: String): android.net.Uri? {
        val f = getArtworkFile(context, identifier)
        return if (f.exists() && f.canRead()) android.net.Uri.fromFile(f) else null
    }
    
    /**
     * Get metadata info file for a song
     */
    private fun getMetadataFile(context: Context, identifier: String): File {
        val songId = generateSongId(identifier)
        return File(getMetadataInfoFolder(context), "$songId.json")
    }
    
    /**
     * Save artwork for a song
     */
    fun saveArtwork(context: Context, identifier: String, artworkBytes: ByteArray): Boolean {
        return try {
            val file = getArtworkFile(context, identifier)
            file.writeBytes(artworkBytes)
            Log.d(TAG, "Saved artwork for $identifier (${artworkBytes.size} bytes)")
            // Best-effort cloud sync (if configured and signed in)
            try { StorageSyncManager.uploadArtworkIfAvailable(context, identifier) } catch (_: Exception) {}
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save artwork for $identifier", e)
            false
        }
    }
    
    /**
     * Save artwork for a song from Bitmap
     */
    fun saveArtwork(context: Context, identifier: String, bitmap: Bitmap, quality: Int = 85): Boolean {
        return try {
            val file = getArtworkFile(context, identifier)
            file.outputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            }
            Log.d(TAG, "Saved bitmap artwork for $identifier")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save bitmap artwork for $identifier", e)
            false
        }
    }
    
    /**
     * Load artwork for a song
     */
    fun loadArtwork(context: Context, identifier: String): ByteArray? {
        return try {
            val file = getArtworkFile(context, identifier)
            if (file.exists() && file.canRead()) {
                val bytes = file.readBytes()
                Log.d(TAG, "Loaded artwork for $identifier (${bytes.size} bytes)")
                bytes
            } else {
                Log.d(TAG, "No artwork file found for $identifier")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load artwork for $identifier", e)
            null
        }
    }
    
    /**
     * Load artwork as Bitmap
     */
    fun loadArtworkBitmap(context: Context, identifier: String): Bitmap? {
        return try {
            val bytes = loadArtwork(context, identifier) ?: return null
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to decode artwork bitmap for $identifier", e)
            null
        }
    }
    
    /**
     * Check if artwork exists for a song
     */
    fun hasArtwork(context: Context, identifier: String): Boolean {
        val file = getArtworkFile(context, identifier)
        return file.exists() && file.length() > 0
    }
    
    /**
     * Save metadata for a song
     */
    fun saveMetadata(context: Context, song: Song): Boolean {
        return try {
            val identifier = song.path.ifBlank { song.title }
            val file = getMetadataFile(context, identifier)
            
            val json = JSONObject().apply {
                put("id", song.id)
                put("title", song.title)
                put("artist", song.artist)
                put("album", song.album)
                put("duration", song.duration)
                put("path", song.path)
                put("size", song.size)
                put("mimeType", song.mimeType)
                put("dateAdded", song.dateAdded)
                put("track", song.track)
                put("year", song.year)
                put("genre", song.genre)
                put("bitrate", song.bitrate)
                put("sampleRate", song.sampleRate)
                put("relativePath", song.relativePath)
                put("timestamp", System.currentTimeMillis())
            }
            
            file.writeText(json.toString(2))
            Log.d(TAG, "Saved metadata for ${song.title}")
            // Best-effort cloud sync (if configured and signed in)
            try { StorageSyncManager.uploadMetadataIfAvailable(context, identifier) } catch (_: Exception) {}
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save metadata", e)
            false
        }
    }
    
    /**
     * Load metadata for a song
     */
    fun loadMetadata(context: Context, identifier: String): Song? {
        return try {
            val file = getMetadataFile(context, identifier)
            if (!file.exists()) {
                Log.d(TAG, "No metadata file found for $identifier")
                return null
            }
            
            val json = JSONObject(file.readText())
            Song(
                id = json.optLong("id", 0L),
                title = json.optString("title", ""),
                artist = json.optString("artist", ""),
                album = json.optString("album", ""),
                duration = json.optLong("duration", 0L),
                path = json.optString("path", ""),
                size = json.optLong("size", 0L),
                mimeType = json.optString("mimeType", ""),
                dateAdded = json.optLong("dateAdded", 0L),
                track = json.optInt("track", 0),
                year = json.optString("year", ""),
                genre = json.optString("genre", ""),
                bitrate = json.optInt("bitrate", 0),
                sampleRate = json.optInt("sampleRate", 0),
                relativePath = json.optString("relativePath", "")
            ).also {
                Log.d(TAG, "Loaded metadata for ${it.title}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load metadata for $identifier", e)
            null
        }
    }
    
    /**
     * Check if metadata exists for a song
     */
    fun hasMetadata(context: Context, identifier: String): Boolean {
        val file = getMetadataFile(context, identifier)
        return file.exists() && file.length() > 0
    }
    
    /**
     * Delete artwork for a song
     */
    fun deleteArtwork(context: Context, identifier: String): Boolean {
        return try {
            val file = getArtworkFile(context, identifier)
            if (file.exists()) {
                file.delete()
                Log.d(TAG, "Deleted artwork for $identifier")
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete artwork for $identifier", e)
            false
        }
    }
    
    /**
     * Delete metadata for a song
     */
    fun deleteMetadata(context: Context, identifier: String): Boolean {
        return try {
            val file = getMetadataFile(context, identifier)
            if (file.exists()) {
                file.delete()
                Log.d(TAG, "Deleted metadata for $identifier")
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete metadata for $identifier", e)
            false
        }
    }
    
    /**
     * Clear all stored metadata and artwork
     */
    fun clearAll(context: Context): Boolean {
        return try {
            var success = true
            getArtworkFolder(context).listFiles()?.forEach { file ->
                if (!file.delete()) success = false
            }
            getMetadataInfoFolder(context).listFiles()?.forEach { file ->
                if (!file.delete()) success = false
            }
            Log.d(TAG, "Cleared all metadata storage")
            success
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear metadata storage", e)
            false
        }
    }
    
    /**
     * Get storage statistics
     */
    fun getStorageStats(context: Context): StorageStats {
        return try {
            val artworkFolder = getArtworkFolder(context)
            val metadataFolder = getMetadataInfoFolder(context)
            
            val artworkCount = artworkFolder.listFiles()?.size ?: 0
            val metadataCount = metadataFolder.listFiles()?.size ?: 0
            
            val artworkSize = artworkFolder.listFiles()?.sumOf { it.length() } ?: 0
            val metadataSize = metadataFolder.listFiles()?.sumOf { it.length() } ?: 0
            
            StorageStats(
                artworkCount = artworkCount,
                metadataCount = metadataCount,
                artworkSize = artworkSize,
                metadataSize = metadataSize,
                totalSize = artworkSize + metadataSize
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get storage stats", e)
            StorageStats(0, 0, 0, 0, 0)
        }
    }
    
    /**
     * Get the folder path for display purposes
     */
    fun getMetadataFolderPath(context: Context): String {
        return getMetadataFolder(context).absolutePath
    }
    
    /**
     * Set custom path for metadata storage
     */
    fun setCustomMetadataPath(context: Context, path: String): Boolean {
        return try {
            val folder = File(path)
            if (!folder.exists()) {
                folder.mkdirs()
            }
            
            if (folder.exists() && folder.isDirectory) {
                val prefs = context.getSharedPreferences("storage_settings", Context.MODE_PRIVATE)
                prefs.edit().putString(CUSTOM_PATH_PREF, path).apply()
                Log.d(TAG, "Custom metadata path set to: $path")
                true
            } else {
                Log.e(TAG, "Failed to create custom path: $path")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set custom metadata path", e)
            false
        }
    }
    
    /**
     * Auto-detect metadata from common locations
     */
    fun autoDetectMetadata(context: Context): File? {
        val commonLocations = listOf(
            File(context.filesDir, METADATA_FOLDER),
            File(context.externalCacheDir, METADATA_FOLDER),
            File(context.getExternalFilesDir(null), METADATA_FOLDER),
            File(context.cacheDir, METADATA_FOLDER),
            // Check Downloads folder
            File(android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOWNLOADS), "metadata")
        )
        
        for (location in commonLocations) {
            val artworkFolder = File(location, ARTWORK_SUBFOLDER)
            val metadataFolder = File(location, METADATA_SUBFOLDER)
            
            if (artworkFolder.exists() || metadataFolder.exists()) {
                Log.d(TAG, "Auto-detected metadata at: ${location.absolutePath}")
                // Save the detected location as custom path
                setCustomMetadataPath(context, location.absolutePath)
                return location
            }
        }
        
        Log.d(TAG, "No metadata found in common locations")
        return null
    }
    
    data class StorageStats(
        val artworkCount: Int,
        val metadataCount: Int,
        val artworkSize: Long,
        val metadataSize: Long,
        val totalSize: Long
    )
}
