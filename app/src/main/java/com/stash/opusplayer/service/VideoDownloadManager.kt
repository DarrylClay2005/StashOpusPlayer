package com.stash.opusplayer.service

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import com.stash.opusplayer.data.DownloadProgress
import com.stash.opusplayer.data.DownloadRequest
import com.stash.opusplayer.data.DownloadStatus
import com.stash.opusplayer.utils.MetadataExtractor
import com.stash.opusplayer.utils.YtDlpExtractor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

class VideoDownloadManager(private val context: Context) {

    companion object {
        private const val TAG = "VideoDownloadManager"
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30000, TimeUnit.MILLISECONDS)
        .readTimeout(30000, TimeUnit.MILLISECONDS)
        .writeTimeout(30000, TimeUnit.MILLISECONDS)
        .build()
    
    private val _downloadProgress = MutableSharedFlow<DownloadProgress>()
    val downloadProgress: SharedFlow<DownloadProgress> = _downloadProgress
    
    private val metadataExtractor = MetadataExtractor(context)
    private val ytDlpExtractor = YtDlpExtractor(context)

    private val activeDownloads = mutableMapOf<String, Boolean>()

    suspend fun startDownload(request: DownloadRequest) = withContext(Dispatchers.IO) {
        val videoId = request.video.id
        val videoTitle = request.video.title
        
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

            Log.d(TAG, "Using local yt-dlp to extract and download audio for: ${request.video.url}")
            
            // Initialize yt-dlp if not already done
            if (!ytDlpExtractor.initialize()) {
                Log.e(TAG, "Failed to initialize yt-dlp")
                throw Exception("Failed to initialize yt-dlp - please check your internet connection")
            }

            // Extract audio URL using yt-dlp
            val audioUrl = ytDlpExtractor.extractAudioUrl(request.video.url)
            
            if (audioUrl != null) {
                Log.i(TAG, "Successfully extracted audio URL using local yt-dlp")
                downloadAudioFile(request, audioUrl)
            } else {
                Log.w(TAG, "yt-dlp extraction failed - this may be due to YouTube changes or network issues")
                throw Exception("Failed to extract audio URL - YouTube may have changed or video is unavailable")
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

    private suspend fun downloadAudioFile(request: DownloadRequest, audioUrl: String) {
        val videoId = request.video.id
        val fileName = "${sanitizeFileName(request.video.title)}.${request.selectedFormat.extension}"

        try {
            // Emit downloading status
            _downloadProgress.emit(
                DownloadProgress(videoId, 0, DownloadStatus.DOWNLOADING)
            )
            
            // Download YouTube thumbnail first
            Log.d(TAG, "Downloading metadata and thumbnail for: ${request.video.title}")
            val thumbnailBase64 = try {
                metadataExtractor.downloadYouTubeThumbnail(videoId)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to download thumbnail, continuing without it", e)
                null
            }
            
            // Prepare output file
            val file = if (request.downloadPath.startsWith("content://")) {
                val treeUri = Uri.parse(request.downloadPath)
                val documentFile = DocumentFile.fromTreeUri(context, treeUri)
                val mimeType = getMimeTypeForFormat(request.selectedFormat.extension)
                documentFile?.createFile(mimeType, fileName)
                    ?: throw Exception("Could not create file in selected directory")
            } else {
                val dir = File(request.downloadPath)
                if (!dir.exists()) dir.mkdirs()
                File(dir, fileName)
            }

            // Download the audio file
            Log.d(TAG, "Starting audio download from: $audioUrl")
            
            val httpRequest = Request.Builder()
                .url(audioUrl)
                .addHeader("User-Agent", "Mozilla/5.0 (Android 11; Mobile; rv:68.0) Gecko/68.0 Firefox/88.0")
                .build()

            val response = client.newCall(httpRequest).execute()

            if (!response.isSuccessful) {
                throw Exception("Failed to download audio: ${response.code}")
            }

            val body = response.body ?: throw Exception("Empty response body")
            
            // Download and save the file
            val inputStream = body.byteStream()
            val outputStream = when (file) {
                is DocumentFile -> context.contentResolver.openOutputStream(file.uri)
                    ?: throw Exception("Could not open output stream")
                is File -> FileOutputStream(file)
                else -> throw Exception("Invalid file type")
            }

            outputStream.use { output ->
                inputStream.use { input ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    var totalBytes = 0L
                    val contentLength = body.contentLength()
                    
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        totalBytes += bytesRead
                        
                        // Report progress if we know the total size
                        if (contentLength > 0) {
                            val progress = ((totalBytes * 100) / contentLength).toInt()
                            if (progress > 0 && progress < 100) {
                                _downloadProgress.tryEmit(
                                    DownloadProgress(videoId, progress, DownloadStatus.DOWNLOADING)
                                )
                            }
                        }
                    }
                }
            }
            
            Log.d(TAG, "Audio download completed, processing metadata...")
            
            // Process metadata
            try {
                val filePath = when (file) {
                    is DocumentFile -> file.uri.toString()
                    is File -> file.absolutePath
                    else -> ""
                }
                
                // Create a Song object with YouTube metadata and thumbnail
                val song = metadataExtractor.createYouTubeSong(
                    videoId = videoId,
                    title = request.video.title,
                    artist = request.video.channelTitle,
                    filePath = filePath,
                    duration = 0L // Duration will be extracted later if needed
                )
                
                // Notify that metadata has been processed
                Log.d(TAG, "Processed metadata for: ${request.video.title}")
                if (song.albumArt != null) {
                    Log.d(TAG, "Thumbnail successfully embedded for: ${request.video.title}")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to process metadata, but audio download succeeded", e)
            }

            // Emit completion
            _downloadProgress.emit(
                DownloadProgress(
                    videoId,
                    100,
                    DownloadStatus.COMPLETED,
                    filePath = when (file) {
                        is DocumentFile -> file.uri.toString()
                        is File -> file.absolutePath
                        else -> ""
                    }
                )
            )
            
            Log.i(TAG, "Download completed successfully: ${request.video.title}")

        } catch (e: Exception) {
            Log.e(TAG, "Audio download failed", e)
            _downloadProgress.emit(
                DownloadProgress(
                    videoId,
                    0,
                    DownloadStatus.FAILED,
                    error = e.message
                )
            )
        }
    }

    private fun sanitizeFileName(fileName: String): String {
        return fileName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
            .take(100) // Limit length
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
    
    /**
     * Update yt-dlp to the latest version
     * This ensures compatibility with YouTube changes
     */
    suspend fun updateYtDlp(): Boolean {
        return ytDlpExtractor.updateYtDlp()
    }
}
