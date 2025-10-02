package com.stash.stashwave.service

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Base64
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import com.stash.stashwave.data.DownloadProgress
import com.stash.stashwave.data.DownloadRequest
import com.stash.stashwave.data.DownloadStatus
import com.stash.stashwave.data.Song
import com.stash.stashwave.utils.MetadataExtractor
import com.stash.stashwave.utils.YtDlpExtractor
import com.stash.stashwave.utils.FfmpegEmbedder
import com.stash.stashwave.utils.TagEditor
import com.stash.stashwave.artwork.ArtworkCache
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File

class VideoDownloadManager(private val context: Context) {

    companion object {
        private const val TAG = "VideoDownloadManager"
    }
    
    private val _downloadProgress = MutableSharedFlow<DownloadProgress>()
    val downloadProgress: SharedFlow<DownloadProgress> = _downloadProgress
    
    private val metadataExtractor = MetadataExtractor(context)
    private val ytDlpExtractor = YtDlpExtractor(context)
    private val customYouTubeService = CustomYouTubeExtractionService(context)
    
    // HTTP client for multi-platform service
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(ExtractionServiceConfig.CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .readTimeout(ExtractionServiceConfig.REQUEST_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .build()
    
    private val activeDownloads = mutableMapOf<String, Boolean>()

    suspend fun startDownload(request: DownloadRequest) = withContext(Dispatchers.IO) {
        val videoId = request.video.id
        val videoTitle = request.video.title
        val videoUrl = request.video.url
        
        Log.i(TAG, "Starting download for: $videoTitle (ID: $videoId)")
        Log.d(TAG, "Format: ${request.selectedFormat.extension} ${request.selectedFormat.quality}")
        Log.d(TAG, "Download path: ${request.downloadPath}")
        
        if (activeDownloads[videoId] == true) {
            Log.w(TAG, "Download already in progress for video: $videoId")
            return@withContext
        }

        activeDownloads[videoId] = true

        try {
            // Emit pending status
            _downloadProgress.emit(
                DownloadProgress(videoId, 0, DownloadStatus.PENDING)
            )

            // Detect platform type from URL
            val platform = customYouTubeService.detectPlatform(videoUrl)
            Log.i(TAG, "🔍 Detected platform: $platform")
            
            // Choose appropriate download method based on platform and auto-detection
            if (platform == "youtube" && ExtractionServiceConfig.AUTO_DETECT_ENABLED) {
                // For YouTube, try yt-dlp first, then auto-detected service as fallback
                Log.i(TAG, "🚀 Starting download with platform-specific logic...")
                downloadWithAutodetect(request)
            } else {
                // For non-YouTube or when auto-detect is disabled, use appropriate method
                if (ExtractionServiceConfig.AUTO_DETECT_ENABLED) {
                    Log.i(TAG, "🌐 Using multi-platform service for $platform...")
                    downloadWithMultiPlatformService(request)
                } else {
                    Log.i(TAG, "🎵 Using yt-dlp download...")
                    downloadWithYtDlpAndFFmpeg(request)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Download failed for $videoTitle", e)
            _downloadProgress.emit(
                DownloadProgress(
                    videoId, 
                    0, 
                    DownloadStatus.FAILED, 
                    error = "Download failed: ${e.message}"
                )
            )
        } finally {
            activeDownloads.remove(videoId)
            Log.d(TAG, "Download process completed for: $videoTitle")
        }
    }

    private suspend fun downloadWithYtDlpAndFFmpeg(request: DownloadRequest) {
        val videoId = request.video.id
        val videoTitle = request.video.title
        val videoUrl = request.video.url
        
        Log.i(TAG, "🚀 Starting yt-dlp + FFmpeg download for: $videoTitle")
        
        try {
            // Initialize yt-dlp
            _downloadProgress.emit(
                DownloadProgress(videoId, 5, DownloadStatus.DOWNLOADING)
            )
            
            Log.d(TAG, "Initializing yt-dlp...")
            if (!ytDlpExtractor.initialize()) {
                throw Exception("Failed to initialize yt-dlp")
            }
            
            // Emit progress for initialization complete
            _downloadProgress.emit(
                DownloadProgress(videoId, 10, DownloadStatus.DOWNLOADING)
            )
            
            // Determine output directory and filename
            val sanitizedTitle = sanitizeFileName(videoTitle)
            val fileExtension = request.selectedFormat.extension
            val fileName = "$sanitizedTitle.$fileExtension"
            
            // Use user-selected download directory or fallback to Downloads folder
            val outputDir = if (request.downloadPath.startsWith("content://")) {
                // For SAF paths, download to internal first then copy
                context.getExternalFilesDir("downloads")!!.absolutePath
            } else {
                // Direct file system path - create directory if needed
                val dir = File(request.downloadPath)
                if (!dir.exists()) {
                    dir.mkdirs()
                    Log.d(TAG, "Created download directory: ${dir.absolutePath}")
                }
                dir.absolutePath
            }
            
            Log.d(TAG, "Download directory: $outputDir")
            Log.d(TAG, "Download filename: $fileName")
            
            // Emit progress before download starts
            _downloadProgress.emit(
                DownloadProgress(videoId, 15, DownloadStatus.DOWNLOADING)
            )
            
            // Start the actual yt-dlp download
            Log.i(TAG, "🎵 Starting yt-dlp audio extraction...")
            val downloadedFilePath = ytDlpExtractor.downloadAudio(
                videoUrl = videoUrl,
                outputDir = outputDir,
                fileName = fileName,
                format = fileExtension
            )
            
            if (downloadedFilePath != null && File(downloadedFilePath).exists()) {
                Log.i(TAG, "✅ yt-dlp download successful!")
                Log.i(TAG, "📁 Downloaded file: $downloadedFilePath")
                Log.i(TAG, "📊 File size: ${File(downloadedFilePath).length()} bytes")
                
                // Emit progress for post-processing
                _downloadProgress.emit(
                    DownloadProgress(videoId, 85, DownloadStatus.DOWNLOADING)
                )
                
                // Handle copying to SAF destination if needed
                val finalPath = if (request.downloadPath.startsWith("content://")) {
                    copyToSAFDestination(downloadedFilePath, request.downloadPath, fileName, fileExtension)
                } else {
                    downloadedFilePath
                }
                
                // Process metadata and thumbnail
                try {
                    _downloadProgress.emit(
                        DownloadProgress(videoId, 90, DownloadStatus.DOWNLOADING)
                    )
                    
                    Log.d(TAG, "Processing metadata and thumbnail...")
                    
                    // Create song metadata entry and cache thumbnail
                    val song = metadataExtractor.createYouTubeSong(
                        videoId = videoId,
                        title = videoTitle,
                        artist = request.video.channelTitle,
                        filePath = finalPath,
                        duration = 0L // Will be detected by media scanner
                    )
                    
                    // Post-process: embed thumbnail if the file lacks embedded art
                    try {
                        embedThumbnailIfMissing(
                            filePath = finalPath,
                            title = song.title,
                            artist = song.artist,
                            album = song.album,
                            youTubeVideoId = videoId
                        )
                    } catch (pp: Exception) {
                        Log.w(TAG, "Post-process embed failed", pp)
                    }
                    
                    Log.i(TAG, "✅ Metadata processing completed")
                } catch (e: Exception) {
                    Log.w(TAG, "Metadata processing failed, but download succeeded", e)
                }
                
                // Emit final success
                _downloadProgress.emit(
                    DownloadProgress(
                        videoId,
                        100,
                        DownloadStatus.COMPLETED,
                        filePath = finalPath
                    )
                )
                
                Log.i(TAG, "🎉 Download completed successfully: $videoTitle")
                
            } else {
                throw Exception("yt-dlp download failed - no output file found")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Download failed for: $videoTitle", e)
            
            // Try to update yt-dlp and retry once
            Log.i(TAG, "🔄 Attempting to update yt-dlp and retry...")
            try {
                if (ytDlpExtractor.updateYtDlp()) {
                    Log.i(TAG, "✅ yt-dlp updated successfully, retrying...")
                    
                    _downloadProgress.emit(
                        DownloadProgress(videoId, 20, DownloadStatus.DOWNLOADING)
                    )
                    
                    // Retry download after update
                    val retryPath = ytDlpExtractor.downloadAudio(
                        videoUrl = request.video.url,
                        outputDir = File(request.downloadPath).absolutePath,
                        fileName = "${sanitizeFileName(videoTitle)}.${request.selectedFormat.extension}",
                        format = request.selectedFormat.extension
                    )
                    
                    if (retryPath != null && File(retryPath).exists()) {
                        Log.i(TAG, "🎉 Retry successful after yt-dlp update!")
                        _downloadProgress.emit(
                            DownloadProgress(videoId, 100, DownloadStatus.COMPLETED, filePath = retryPath)
                        )
                        return
                    }
                }
            } catch (retryException: Exception) {
                Log.e(TAG, "Retry after update also failed", retryException)
            }
            
            throw e // Re-throw original exception
        }
    }
    
    /**
     * Auto-detect download method - tries the best approach for each platform
     */
    private suspend fun downloadWithAutodetect(request: DownloadRequest) {
        val videoId = request.video.id
        val videoUrl = request.video.url
        val outputDir = getOutputDirectory(request)
        val fileName = "${sanitizeFileName(request.video.title)}.${request.selectedFormat.extension}"
        
        try {
            Log.i(TAG, "🔄 Auto-detecting best download method...")
            
            val result = customYouTubeService.downloadAudioAuto(
                videoUrl = videoUrl,
                outputDir = outputDir,
                format = request.selectedFormat.extension,
                quality = request.selectedFormat.quality ?: "good"
            )
            
            if (result.isSuccess) {
                val downloadedPath = result.getOrNull()!!
                handleSuccessfulDownload(request, downloadedPath)
            } else {
                throw Exception("Auto-detection download failed: ${result.exceptionOrNull()?.message}")
            }
            
        } catch (e: Exception) {
            Log.w(TAG, "Auto-detection failed, falling back to yt-dlp", e)
            downloadWithYtDlpAndFFmpeg(request)
        }
    }
    
    /**
     * Multi-platform service download method
     */
    private suspend fun downloadWithMultiPlatformService(request: DownloadRequest) {
        val videoId = request.video.id
        val videoUrl = request.video.url
        val outputDir = getOutputDirectory(request)
        val fileName = "${sanitizeFileName(request.video.title)}.${request.selectedFormat.extension}"
        
        try {
            Log.i(TAG, "🌐 Using multi-platform service...")
            
            _downloadProgress.emit(
                DownloadProgress(videoId, 10, DownloadStatus.DOWNLOADING)
            )
            
            // Get the auto-detected service URL
            val serviceUrl = ExtractionServiceConfig.getServiceUrl(context)
            Log.i(TAG, "🔗 Using service: $serviceUrl")
            
            // Build request URL
            val requestUrl = "$serviceUrl/$videoUrl?format=${request.selectedFormat.extension}&quality=${request.selectedFormat.quality ?: "good"}"
            
            _downloadProgress.emit(
                DownloadProgress(videoId, 20, DownloadStatus.DOWNLOADING)
            )
            
            // Make HTTP request
            val httpRequest = Request.Builder()
                .url(requestUrl)
                .get()
                .build()
            
            val response = httpClient.newCall(httpRequest).execute()
            
            if (!response.isSuccessful) {
                throw Exception("Multi-platform service returned ${response.code}: ${response.message}")
            }
            
            _downloadProgress.emit(
                DownloadProgress(videoId, 50, DownloadStatus.DOWNLOADING)
            )
            
            // Save downloaded file
            val outputFile = File(outputDir, fileName)
            outputFile.parentFile?.mkdirs()
            
            response.body?.byteStream()?.use { inputStream ->
                outputFile.outputStream().use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
            } ?: throw Exception("Empty response from multi-platform service")
            
            _downloadProgress.emit(
                DownloadProgress(videoId, 80, DownloadStatus.DOWNLOADING)
            )
            
            if (outputFile.exists() && outputFile.length() > 0) {
                Log.i(TAG, "✅ Multi-platform download successful!")
                handleSuccessfulDownload(request, outputFile.absolutePath)
            } else {
                throw Exception("Downloaded file is empty or doesn't exist")
            }
            
        } catch (e: Exception) {
            Log.w(TAG, "Multi-platform service failed, falling back to yt-dlp", e)
            downloadWithYtDlpAndFFmpeg(request)
        }
    }
    
    /**
     * Handle successful download completion
     */
    private suspend fun handleSuccessfulDownload(request: DownloadRequest, downloadedPath: String) {
        val videoId = request.video.id
        
        try {
            // Handle SAF copying if needed
            val finalPath = if (request.downloadPath.startsWith("content://")) {
                copyToSAFDestination(downloadedPath, request.downloadPath, 
                    File(downloadedPath).name, request.selectedFormat.extension)
            } else {
                downloadedPath
            }
            
            _downloadProgress.emit(
                DownloadProgress(videoId, 90, DownloadStatus.DOWNLOADING)
            )
            
            // Process metadata
            try {
                val song = metadataExtractor.createYouTubeSong(
                    videoId = videoId,
                    title = request.video.title,
                    artist = request.video.channelTitle,
                    filePath = finalPath,
                    duration = 0L
                )
                // Post-process: embed thumbnail if missing
                try {
                    embedThumbnailIfMissing(
                        filePath = finalPath,
                        title = song.title,
                        artist = song.artist,
                        album = song.album,
                        youTubeVideoId = videoId
                    )
                } catch (pp: Exception) {
                    Log.w(TAG, "Post-process embed failed", pp)
                }
                Log.i(TAG, "✅ Metadata processing completed")
            } catch (e: Exception) {
                Log.w(TAG, "Metadata processing failed, but download succeeded", e)
            }
            
            // Emit final success
            _downloadProgress.emit(
                DownloadProgress(
                    videoId,
                    100,
                    DownloadStatus.COMPLETED,
                    filePath = finalPath
                )
            )
            
            Log.i(TAG, "🎉 Download completed successfully: ${request.video.title}")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in post-processing", e)
            throw e
        }
    }
    
    /**
     * Attempt to embed a thumbnail into the downloaded audio if it has no embedded art.
     * Prefers FFmpegKit when available; falls back to TagEditor for MP3/other formats.
     */
    private suspend fun embedThumbnailIfMissing(
        filePath: String,
        title: String,
        artist: String,
        album: String,
        youTubeVideoId: String
    ) = withContext(Dispatchers.IO) {
        try {
            if (hasEmbeddedArt(filePath)) return@withContext

            // Try to source artwork bytes from cache first
            val artBytesFromCache = tryLoadArtworkFromCache(title, artist, album)
            val artBytes = artBytesFromCache ?: run {
                // Fallback: fetch YouTube thumbnail via MetadataExtractor (returns Base64)
                val b64 = try { metadataExtractor.downloadYouTubeThumbnail(youTubeVideoId) } catch (_: Exception) { null }
                if (!b64.isNullOrBlank()) Base64.decode(b64, Base64.DEFAULT) else null
            }
            if (artBytes == null || artBytes.isEmpty()) return@withContext

            val ok = if (FfmpegEmbedder.isAvailable()) {
                FfmpegEmbedder.embedArtwork(context, filePath, artBytes)
            } else {
                // Fallback to pure Java tag editors
                val ext = filePath.substringAfterLast('.', "").lowercase()
                if (ext == "mp3") TagEditor.embedArtworkMp3(context, filePath, artBytes)
                else TagEditor.embedArtworkAny(context, filePath, artBytes)
            }
            if (ok) Log.i(TAG, "✅ Embedded thumbnail into: $filePath") else Log.w(TAG, "❌ Failed to embed thumbnail for: $filePath")
        } catch (e: Exception) {
            Log.w(TAG, "Embed step failed", e)
        }
    }

    private fun hasEmbeddedArt(path: String): Boolean {
        val mmr = MediaMetadataRetriever()
        return try {
            if (path.startsWith("content://")) {
                mmr.setDataSource(context, Uri.parse(path))
            } else {
                mmr.setDataSource(path)
            }
            mmr.embeddedPicture != null
        } catch (_: Exception) {
            false
        } finally {
            try { mmr.release() } catch (_: Exception) {}
        }
    }

    private fun tryLoadArtworkFromCache(title: String, artist: String, album: String): ByteArray? {
        return try {
            val cache = ArtworkCache(context)
            // Build a lightweight Song only for cache keying
            val song = Song(
                id = (title + artist + album).hashCode().toLong(),
                title = title,
                artist = artist,
                album = album,
                duration = 0L,
                path = "",
                size = 0L,
                mimeType = "",
                dateAdded = 0L
            )
            val bmp = cache.loadBitmapIfPresent(song, 512)
                ?: cache.loadBitmapByTitleIfPresent(title, 512)
            if (bmp != null) {
                ByteArrayOutputStream().use { baos ->
                    bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, baos)
                    baos.toByteArray()
                }
            } else null
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Get output directory for download
     */
    private fun getOutputDirectory(request: DownloadRequest): String {
        return if (request.downloadPath.startsWith("content://")) {
            context.getExternalFilesDir("downloads")!!.absolutePath
        } else {
            val dir = File(request.downloadPath)
            if (!dir.exists()) {
                dir.mkdirs()
                Log.d(TAG, "Created download directory: ${dir.absolutePath}")
            }
            dir.absolutePath
        }
    }
    
    private fun copyToSAFDestination(sourcePath: String, destinationUri: String, fileName: String, extension: String): String {
        return try {
            Log.d(TAG, "Copying file to SAF destination...")
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists()) {
                Log.e(TAG, "Source file does not exist: $sourcePath")
                return sourcePath
            }
            
            val treeUri = Uri.parse(destinationUri)
            val documentFile = DocumentFile.fromTreeUri(context, treeUri)
            val mimeType = getMimeTypeForFormat(extension)
            val destinationFile = documentFile?.createFile(mimeType, fileName)
            
            if (destinationFile != null) {
                context.contentResolver.openOutputStream(destinationFile.uri)?.use { output ->
                    sourceFile.inputStream().use { input ->
                        input.copyTo(output)
                    }
                }
                
                // Delete the temporary file
                sourceFile.delete()
                Log.i(TAG, "✅ File copied to SAF destination successfully")
                return destinationFile.uri.toString()
            } else {
                Log.e(TAG, "Failed to create destination file in SAF")
                return sourcePath
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error copying to SAF destination", e)
            sourcePath
        }
    }
    
    private fun getMimeTypeForFormat(extension: String): String {
        return when (extension.lowercase()) {
            "mp3" -> "audio/mpeg"
            "opus", "webm" -> "audio/webm"
            "m4a" -> "audio/mp4"
            "aac" -> "audio/aac"
            "flac" -> "audio/flac"
            "ogg" -> "audio/ogg"
            else -> "audio/*"
        }
    }
    
    private fun sanitizeFileName(fileName: String): String {
        return fileName.replace(Regex("[^a-zA-Z0-9._\\-\\s]"), "_")
            .replace(Regex("\\s+"), "_")
            .take(100)
    }

    fun cancelDownload(videoId: String) {
        activeDownloads[videoId] = false
        _downloadProgress.tryEmit(
            DownloadProgress(videoId, 0, DownloadStatus.CANCELLED)
        )
    }

    fun isDownloadActive(videoId: String): Boolean {
        return activeDownloads[videoId] == true
    }

    /**
     * Get available audio formats (simplified)
     */
    suspend fun getAvailableFormats(videoUrl: String): Result<List<com.stash.stashwave.data.AudioFormat>> {
        return Result.success(getDefaultFormats())
    }

    private fun getDefaultFormats(): List<com.stash.stashwave.data.AudioFormat> {
        return listOf(
            com.stash.stashwave.data.AudioFormat("opus-best", "opus", "Best", "160", "opus", null),
            com.stash.stashwave.data.AudioFormat("m4a-best", "m4a", "Best", "256", "aac", null),
            com.stash.stashwave.data.AudioFormat("mp3-best", "mp3", "Best", "320", "mp3", null),
            com.stash.stashwave.data.AudioFormat("mp3-good", "mp3", "Good", "192", "mp3", null),
            com.stash.stashwave.data.AudioFormat("opus-good", "opus", "Good", "128", "opus", null),
            com.stash.stashwave.data.AudioFormat("m4a-good", "m4a", "Good", "128", "aac", null),
            com.stash.stashwave.data.AudioFormat("mp3-medium", "mp3", "Medium", "128", "mp3", null)
        )
    }

    /**
     * Update yt-dlp to latest version
     */
    suspend fun updateYtDlp(): Result<Boolean> {
        return try {
            Log.i(TAG, "🔄 Updating yt-dlp...")
            val success = ytDlpExtractor.updateYtDlp()
            if (success) {
                Log.i(TAG, "✅ yt-dlp updated successfully")
                Result.success(true)
            } else {
                Log.w(TAG, "❌ yt-dlp update failed")
                Result.failure(Exception("yt-dlp update failed"))
            }
        } catch (e: Exception) {
            Log.e(TAG, "yt-dlp update error", e)
            Result.failure(e)
        }
    }
}