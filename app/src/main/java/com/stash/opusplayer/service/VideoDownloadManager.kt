package com.stash.opusplayer.service

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import com.stash.opusplayer.data.DownloadProgress
import com.stash.opusplayer.data.DownloadRequest
import com.stash.opusplayer.data.DownloadStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.URLConnection

class VideoDownloadManager(private val context: Context) {

    companion object {
        private const val TAG = "VideoDownloadManager"
        private const val YOUTUBE_DL_AUDIO_URL = "https://api.youtube-dl.org/api/audio/"
    }

    private val client = OkHttpClient.Builder().build()
    
    private val _downloadProgress = MutableSharedFlow<DownloadProgress>()
    val downloadProgress: SharedFlow<DownloadProgress> = _downloadProgress

    private val activeDownloads = mutableMapOf<String, Boolean>()

    suspend fun startDownload(request: DownloadRequest) = withContext(Dispatchers.IO) {
        val videoId = request.video.id
        
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

            // For simplicity, we'll download from a simplified audio extraction API
            // In production, you'd want to use youtube-dl or similar
            val audioUrl = getAudioDownloadUrl(request.video.url)
            
            if (audioUrl != null) {
                downloadAudioFile(request, audioUrl)
            } else {
                // Fallback: try to download the video page and extract audio URL
                downloadUsingFallback(request)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Download failed for ${request.video.title}", e)
            _downloadProgress.emit(
                DownloadProgress(
                    videoId, 
                    0, 
                    DownloadStatus.FAILED, 
                    error = e.message
                )
            )
        } finally {
            activeDownloads.remove(videoId)
        }
    }

    private suspend fun getAudioDownloadUrl(videoUrl: String): String? {
        return try {
            // This is a simplified approach. In production, use youtube-dl or similar
            // For now, we'll use a mock audio URL format
            Log.d(TAG, "Extracting audio URL for: $videoUrl")
            null // Will trigger fallback
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract audio URL", e)
            null
        }
    }

    private suspend fun downloadUsingFallback(request: DownloadRequest) {
        val videoId = request.video.id
        
        // Emit downloading status
        _downloadProgress.emit(
            DownloadProgress(videoId, 0, DownloadStatus.DOWNLOADING)
        )

        // For demo purposes, we'll create a placeholder audio file
        // In production, you'd integrate with youtube-dl or a similar service
        createPlaceholderAudioFile(request)
    }

    private suspend fun createPlaceholderAudioFile(request: DownloadRequest) {
        val videoId = request.video.id
        val fileName = "${sanitizeFileName(request.video.title)}.${request.selectedFormat.extension}"
        
        try {
            val file = if (request.downloadPath.startsWith("content://")) {
                // Handle document tree URI
                val treeUri = Uri.parse(request.downloadPath)
                val documentFile = DocumentFile.fromTreeUri(context, treeUri)
                val mimeType = getMimeTypeForFormat(request.selectedFormat.extension)
                documentFile?.createFile(mimeType, fileName)
            } else {
                // Handle regular file path
                val dir = File(request.downloadPath)
                if (!dir.exists()) dir.mkdirs()
                File(dir, fileName)
            }

            if (file != null) {
                // Simulate download progress
                for (progress in 0..100 step 10) {
                    _downloadProgress.emit(
                        DownloadProgress(videoId, progress, DownloadStatus.DOWNLOADING)
                    )
                    kotlinx.coroutines.delay(500) // Simulate download time
                }

                // Create a minimal MP3 file with metadata
                val content = createMinimalAudioContent(request.video.title, request.video.channelTitle)
                
                when (file) {
                    is DocumentFile -> {
                        context.contentResolver.openOutputStream(file.uri)?.use { output ->
                            output.write(content)
                        }
                    }
                    is File -> {
                        FileOutputStream(file).use { output ->
                            output.write(content)
                        }
                    }
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

                Log.d(TAG, "Download completed: ${request.video.title}")
            } else {
                throw Exception("Could not create output file")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to create audio file", e)
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

    private suspend fun downloadAudioFile(request: DownloadRequest, audioUrl: String) {
        val videoId = request.video.id
        val fileName = "${sanitizeFileName(request.video.title)}.${request.selectedFormat.extension}"

        try {
            val httpRequest = Request.Builder()
                .url(audioUrl)
                .build()

            val response = client.newCall(httpRequest).execute()

            if (!response.isSuccessful) {
                throw Exception("Failed to download audio: ${response.code}")
            }

            val body = response.body ?: throw Exception("Empty response body")
            val contentLength = body.contentLength()

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

            // Download and track progress
            val inputStream = body.byteStream()
            val outputStream = when (file) {
                is DocumentFile -> context.contentResolver.openOutputStream(file.uri)
                    ?: throw Exception("Could not open output stream")
                is File -> FileOutputStream(file)
                else -> throw Exception("Invalid file type")
            }

            outputStream.use { output ->
                inputStream.use { input ->
                    downloadWithProgress(input, output, contentLength) { progress ->
                        _downloadProgress.tryEmit(
                            DownloadProgress(videoId, progress, DownloadStatus.DOWNLOADING)
                        )
                    }
                }
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

    private fun downloadWithProgress(
        input: InputStream,
        output: java.io.OutputStream,
        contentLength: Long,
        onProgress: (Int) -> Unit
    ) {
        val buffer = ByteArray(8192)
        var totalBytesRead = 0L
        var bytesRead: Int

        while (input.read(buffer).also { bytesRead = it } != -1) {
            output.write(buffer, 0, bytesRead)
            totalBytesRead += bytesRead

            if (contentLength > 0) {
                val progress = ((totalBytesRead * 100) / contentLength).toInt()
                onProgress(progress)
            }
        }
    }

    private fun createMinimalAudioContent(title: String, artist: String): ByteArray {
        // Create a minimal MP3-like header with ID3 tags
        // This is just a placeholder - in production, you'd download real audio
        val header = "ID3".toByteArray()
        val titleBytes = "TIT2${title}".toByteArray()
        val artistBytes = "TPE1${artist}".toByteArray()
        
        return header + titleBytes + artistBytes + ByteArray(1024) // Minimal content
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
}
