package com.stash.stashwave.utils

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

    suspend fun downloadAudio(videoUrl: String, outputDir: String, fileName: String, format: String): String? = withContext(Dispatchers.IO) {
        return@withContext try {
            if (!isInitialized) {
                Log.w(TAG, "yt-dlp not initialized, attempting to initialize...")
                if (!initialize()) {
                    return@withContext null
                }
            }

            Log.i(TAG, "🎵 Starting yt-dlp audio download for: $videoUrl")
            Log.d(TAG, "Output directory: $outputDir")
            Log.d(TAG, "Base filename: $fileName")
            Log.d(TAG, "Format: $format")

            // Create output directory if it doesn't exist
            val outputDirFile = File(outputDir)
            if (!outputDirFile.exists()) {
                outputDirFile.mkdirs()
                Log.d(TAG, "Created output directory: $outputDir")
            }

            // Create output template for yt-dlp (without extension, yt-dlp will add it)
            val baseFileName = fileName.substringBeforeLast('.')
            val outputTemplate = File(outputDirFile, baseFileName).absolutePath
            
            Log.d(TAG, "yt-dlp output template: $outputTemplate")

            // Configure yt-dlp request for audio-only download
            val request = YoutubeDLRequest(videoUrl).apply {
                // Extract audio only
                addOption("-x")
                
                // Set audio format and quality
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
                    "ogg" -> {
                        addOption("--audio-format", "vorbis")
                        addOption("--audio-quality", "0")
                    }
                    else -> {
                        // Default to mp3
                        addOption("--audio-format", "mp3")
                        addOption("--audio-quality", "0")
                    }
                }
                
                // Set output template (yt-dlp will add proper extension)
                addOption("-o", "$outputTemplate.%(ext)s")
                
                // Basic options for Android compatibility
                addOption("--no-check-certificate")
                addOption("--prefer-ffmpeg")
                
                // Metadata and thumbnail
                addOption("--write-info-json")
                addOption("--write-thumbnail")
                
                // Anti-detection measures
                addOption("--user-agent", "Mozilla/5.0 (Linux; Android 11; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
                addOption("--referer", "https://www.youtube.com/")
                
                // Error handling
                addOption("--ignore-errors")
                addOption("--no-abort-on-error")
                
                // Retries
                addOption("--retries", "5")
                addOption("--fragment-retries", "5")
                addOption("--retry-sleep", "1")
                
                // Verbose logging
                addOption("--verbose")
                addOption("--print-traffic")
            }

            Log.i(TAG, "🚀 Executing yt-dlp download with enhanced Android settings...")
            val response = YoutubeDL.getInstance().execute(request)
            
            Log.d(TAG, "yt-dlp exit code: ${response.exitCode}")
            Log.d(TAG, "yt-dlp output: ${response.out}")
            if (response.err.isNotEmpty()) {
                Log.w(TAG, "yt-dlp errors: ${response.err}")
            }
            
            // Look for the downloaded file (yt-dlp may change the extension)
            val possibleExtensions = listOf(format, "mp3", "m4a", "opus", "webm", "ogg")
            var actualOutputFile: File? = null
            
            for (ext in possibleExtensions) {
                val testFile = File(outputDirFile, "$baseFileName.$ext")
                if (testFile.exists()) {
                    actualOutputFile = testFile
                    Log.i(TAG, "✅ Found downloaded file: ${testFile.absolutePath}")
                    break
                }
            }
            
            if (actualOutputFile?.exists() == true) {
                Log.i(TAG, "✅ yt-dlp download completed successfully!")
                Log.i(TAG, "📁 File saved as: ${actualOutputFile.absolutePath}")
                Log.i(TAG, "📊 File size: ${actualOutputFile.length()} bytes")
                return@withContext actualOutputFile.absolutePath
            } else {
                // List files in output directory for debugging
                Log.w(TAG, "❌ No output file found. Directory contents:")
                outputDirFile.listFiles()?.forEach { file ->
                    Log.w(TAG, "   📄 ${file.name} (${file.length()} bytes)")
                }
                
                if (response.exitCode != 0) {
                    Log.e(TAG, "❌ yt-dlp failed with exit code: ${response.exitCode}")
                    Log.e(TAG, "❌ Error output: ${response.err}")
                }
                
                return@withContext null
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ yt-dlp download failed with exception", e)
            null
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

    /**
     * Resolve a direct best-audio stream URL suitable for streaming (not downloading).
     */
    suspend fun getBestAudioStreamUrl(videoUrl: String): String? = withContext(Dispatchers.IO) {
        return@withContext try {
            if (!isInitialized) {
                if (!initialize()) return@withContext null
            }
            Log.d(TAG, "Resolving best audio stream URL for: $videoUrl")

            // Try multiple selectors for better compatibility
            val selectors = listOf(
                "bestaudio[ext=webm]",
                "bestaudio[ext=m4a]",
                "bestaudio"
            )
            var resolved: String? = null
            for (sel in selectors) {
                val request = YoutubeDLRequest(videoUrl).apply {
                    addOption("-f", sel)
                    addOption("-g") // get direct URL
                    addOption("--no-playlist")
                }
                val response = YoutubeDL.getInstance().execute(request)
                val out = response.out.trim()
                val url = out.lineSequence().lastOrNull()?.trim()
                Log.d(TAG, "Selector '$sel' returned: ${url?.take(80)}")
                if (!url.isNullOrBlank() && (url.startsWith("http://") || url.startsWith("https://"))) {
                    resolved = url
                    break
                }
            }
            if (resolved != null) {
                Log.d(TAG, "Resolved audio stream URL: $resolved")
            } else {
                Log.w(TAG, "No audio stream URL could be resolved after trying selectors")
            }
            resolved
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resolve audio stream URL", e)
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
