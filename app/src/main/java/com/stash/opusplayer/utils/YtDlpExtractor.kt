package com.stash.opusplayer.utils

import android.content.Context
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class YtDlpExtractor(private val context: Context) {

    companion object {
        private const val TAG = "YtDlpExtractor"
    }

    private var isInitialized = false

    suspend fun initialize(): Boolean = withContext(Dispatchers.IO) {
        return@withContext try {
            if (isInitialized) return@withContext true
            
            Log.d(TAG, "Initializing yt-dlp...")
            YoutubeDL.getInstance().init(context)
            isInitialized = true
            Log.i(TAG, "yt-dlp initialized successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize yt-dlp", e)
            false
        }
    }

    suspend fun extractAudioUrl(videoUrl: String): String? = withContext(Dispatchers.IO) {
        return@withContext try {
            if (!isInitialized) {
                Log.w(TAG, "yt-dlp not initialized, attempting to initialize...")
                if (!initialize()) {
                    return@withContext null
                }
            }

            Log.d(TAG, "Extracting audio URL for: $videoUrl")

            val request = YoutubeDLRequest(videoUrl).apply {
                // Extract best audio only
                addOption("-f", "bestaudio/best")
                // Get URL only, don't download
                addOption("--get-url")
                // Prefer specific audio formats
                addOption("--prefer-free-formats")
                // Add user agent to avoid bot detection
                addOption("--user-agent", "Mozilla/5.0 (Android 11; Mobile; rv:68.0) Gecko/68.0 Firefox/88.0")
                // Add headers to appear more like a browser
                addOption("--add-header", "Accept-Language:en-US,en;q=0.9")
                addOption("--add-header", "Accept:text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
            }

            val response = YoutubeDL.getInstance().execute(request)
            val audioUrl = response.out.trim()

            if (audioUrl.isNotEmpty() && (audioUrl.startsWith("http") || audioUrl.startsWith("https"))) {
                Log.i(TAG, "Successfully extracted audio URL")
                Log.d(TAG, "Audio URL: $audioUrl")
                return@withContext audioUrl
            } else {
                Log.w(TAG, "No valid audio URL found in response: $audioUrl")
                return@withContext null
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract audio URL", e)
            null
        }
    }

    suspend fun getVideoInfo(videoUrl: String): VideoInfo? = withContext(Dispatchers.IO) {
        return@withContext try {
            if (!isInitialized) {
                if (!initialize()) return@withContext null
            }

            Log.d(TAG, "Getting video info for: $videoUrl")

            val request = YoutubeDLRequest(videoUrl).apply {
                // Get JSON info without downloading
                addOption("--dump-json")
                addOption("--no-download")
                addOption("--user-agent", "Mozilla/5.0 (Android 11; Mobile; rv:68.0) Gecko/68.0 Firefox/88.0")
            }

            val response = YoutubeDL.getInstance().execute(request)
            val jsonOutput = response.out

            if (jsonOutput.isNotEmpty()) {
                return@withContext parseVideoInfo(jsonOutput)
            } else {
                Log.w(TAG, "Empty response from yt-dlp info extraction")
                return@withContext null
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to get video info", e)
            null
        }
    }

    private fun parseVideoInfo(jsonOutput: String): VideoInfo? {
        return try {
            // Basic JSON parsing for video info
            // In a production app, you'd want to use a proper JSON library
            val title = extractJsonValue(jsonOutput, "title") ?: "Unknown Title"
            val uploader = extractJsonValue(jsonOutput, "uploader") ?: "Unknown Channel"
            val duration = extractJsonValue(jsonOutput, "duration")?.toIntOrNull() ?: 0
            val thumbnail = extractJsonValue(jsonOutput, "thumbnail")

            VideoInfo(
                title = title,
                uploader = uploader,
                duration = duration,
                thumbnailUrl = thumbnail
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse video info JSON", e)
            null
        }
    }

    private fun extractJsonValue(json: String, key: String): String? {
        return try {
            val pattern = "\"$key\"\\s*:\\s*\"([^\"]+)\"".toRegex()
            val match = pattern.find(json)
            match?.groupValues?.get(1)
        } catch (e: Exception) {
            null
        }
    }

    suspend fun updateYtDlp(): Boolean = withContext(Dispatchers.IO) {
        return@withContext try {
            Log.d(TAG, "Updating yt-dlp...")
            YoutubeDL.getInstance().updateYoutubeDL(context)
            Log.i(TAG, "yt-dlp updated successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update yt-dlp", e)
            false
        }
    }

    data class VideoInfo(
        val title: String,
        val uploader: String,
        val duration: Int, // in seconds
        val thumbnailUrl: String?
    )
}
