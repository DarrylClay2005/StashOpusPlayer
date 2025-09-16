package com.stash.opusplayer.utils

import android.content.Context
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class YtDlpExtractor(private val context: Context) {

    companion object {
        private const val TAG = "YtDlpExtractor"
    }

    private var isInitialized = false

    suspend fun initialize(): Boolean = withContext(Dispatchers.IO) {
        return@withContext try {
            if (isInitialized) return@withContext true
            
            Log.i(TAG, "Initializing yt-dlp for reliable YouTube downloads...")
            YoutubeDL.getInstance().init(context)
            isInitialized = true
            Log.i(TAG, "✅ yt-dlp initialized successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize yt-dlp", e)
            false
        }
    }

    suspend fun downloadAudio(videoUrl: String, outputPath: String, format: String): Boolean = withContext(Dispatchers.IO) {
        return@withContext try {
            if (!isInitialized) {
                Log.w(TAG, "yt-dlp not initialized, attempting to initialize...")
                if (!initialize()) {
                    return@withContext false
                }
            }

            Log.i(TAG, "🎵 Starting yt-dlp audio download for: $videoUrl")
            Log.d(TAG, "Output path: $outputPath")
            Log.d(TAG, "Format: $format")

            // Create output directory if it doesn't exist
            val outputFile = File(outputPath)
            val outputDir = outputFile.parentFile
            if (outputDir != null && !outputDir.exists()) {
                outputDir.mkdirs()
            }

            // Configure yt-dlp request for audio-only download
            val request = YoutubeDLRequest(videoUrl).apply {
                // Extract audio only
                addOption("-x")
                
                // Set audio format
                when (format.lowercase()) {
                    "mp3" -> {
                        addOption("--audio-format", "mp3")
                        addOption("--audio-quality", "0") // Best quality
                    }
                    "m4a", "aac" -> {
                        addOption("--audio-format", "m4a")
                        addOption("--audio-quality", "0")
                    }
                    "opus", "webm" -> {
                        addOption("--audio-format", "opus")
                        addOption("--audio-quality", "0")
                    }
                    else -> {
                        addOption("--audio-format", "mp3")
                        addOption("--audio-quality", "0")
                    }
                }
                
                // Set output path
                addOption("-o", outputPath)
                
                // Enhanced options for reliability
                addOption("--embed-thumbnail") // Embed thumbnail
                addOption("--add-metadata") // Add metadata
                addOption("--prefer-ffmpeg") // Use FFmpeg for processing
                addOption("--ffmpeg-location", "ffmpeg") // Use system FFmpeg
                
                // Anti-detection measures
                addOption("--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                addOption("--referer", "https://www.youtube.com/")
                
                // Skip unavailable content
                addOption("--ignore-errors")
                addOption("--no-abort-on-error")
                
                // Retry on failure
                addOption("--retries", "3")
                addOption("--fragment-retries", "3")
                
                // Verbose for debugging
                addOption("--verbose")
            }

            Log.i(TAG, "🚀 Executing yt-dlp download...")
            val response = YoutubeDL.getInstance().execute(request)
            
            if (response.exitCode == 0) {
                Log.i(TAG, "✅ yt-dlp download completed successfully!")
                Log.d(TAG, "Output: ${response.out}")
                return@withContext true
            } else {
                Log.w(TAG, "⚠️ yt-dlp download completed with warnings")
                Log.w(TAG, "Exit code: ${response.exitCode}")
                Log.w(TAG, "Output: ${response.out}")
                Log.w(TAG, "Error: ${response.err}")
                
                // Check if file was created despite warnings
                val outputFileExists = File(outputPath).exists() || 
                                     File(outputPath.replace(Regex("\\.[^.]+$"), ".mp3")).exists() ||
                                     File(outputPath.replace(Regex("\\.[^.]+$"), ".m4a")).exists() ||
                                     File(outputPath.replace(Regex("\\.[^.]+$"), ".opus")).exists()
                                     
                if (outputFileExists) {
                    Log.i(TAG, "✅ File was created despite warnings - considering success")
                    return@withContext true
                }
                
                return@withContext false
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ yt-dlp download failed", e)
            false
        }
    }

    suspend fun updateYtDlp(): Boolean = withContext(Dispatchers.IO) {
        return@withContext try {
            Log.i(TAG, "🔄 Updating yt-dlp...")
            YoutubeDL.getInstance().updateYoutubeDL(context)
            Log.i(TAG, "✅ yt-dlp updated successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update yt-dlp", e)
            false
        }
    }

    suspend fun getVideoInfo(videoUrl: String): VideoInfo? = withContext(Dispatchers.IO) {
        return@withContext try {
            if (!isInitialized) {
                if (!initialize()) return@withContext null
            }

            Log.d(TAG, "🔍 Getting video info for: $videoUrl")

            val request = YoutubeDLRequest(videoUrl).apply {
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

    data class VideoInfo(
        val title: String,
        val uploader: String,
        val duration: Int, // in seconds
        val thumbnailUrl: String?
    )
}
