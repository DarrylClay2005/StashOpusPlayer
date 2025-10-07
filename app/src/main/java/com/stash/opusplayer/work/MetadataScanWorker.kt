package com.stash.opusplayer.work

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.work.*
import com.stash.opusplayer.data.MetadataDao
import com.stash.opusplayer.data.MetadataInfo
import com.stash.opusplayer.data.MusicRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.TimeUnit

class MetadataScanWorker(
    context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    companion object {
        const val TAG = "MetadataScanWorker"
        const val WORK_NAME = "metadata_scan_work"
        const val KEY_FILE_PATHS = "file_paths"
        const val KEY_FORCE_RESCAN = "force_rescan"
        
        fun scheduleMetadataScan(context: Context, filePaths: List<String>? = null, forceRescan: Boolean = false) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                .setRequiresBatteryNotLow(true)
                .build()

            val inputData = Data.Builder()
                .putBoolean(KEY_FORCE_RESCAN, forceRescan)
                .apply {
                    filePaths?.let { putStringArray(KEY_FILE_PATHS, it.toTypedArray()) }
                }
                .build()

            val request = OneTimeWorkRequestBuilder<MetadataScanWorker>()
                .setConstraints(constraints)
                .setInputData(inputData)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
        }
        
        fun schedulePeriodicMetadataScan(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                .setRequiresBatteryNotLow(true)
                .setRequiresDeviceIdle(true)
                .build()

            val request = PeriodicWorkRequestBuilder<MetadataScanWorker>(6, TimeUnit.HOURS)
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.HOURS)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork("periodic_metadata_scan", ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Starting metadata scan work")
            
            val repository = MusicRepository(applicationContext)
            val metadataDao = repository.metadataDao
            
            val filePaths = inputData.getStringArray(KEY_FILE_PATHS)?.toList()
            val forceRescan = inputData.getBoolean(KEY_FORCE_RESCAN, false)
            
            if (filePaths != null) {
                // Scan specific files
                scanSpecificFiles(metadataDao, filePaths, forceRescan)
            } else {
                // Scan all music files
                scanAllMusicFiles(repository, metadataDao, forceRescan)
            }
            
            Log.d(TAG, "Metadata scan completed successfully")
            Result.success()
            
        } catch (e: Exception) {
            Log.e(TAG, "Metadata scan failed", e)
            Result.retry()
        }
    }
    
    private suspend fun scanSpecificFiles(
        metadataDao: MetadataDao, 
        filePaths: List<String>, 
        forceRescan: Boolean
    ) {
        Log.d(TAG, "Scanning ${filePaths.size} specific files")
        
        for (filePath in filePaths) {
            try {
                // Check if we need to scan this file
                val existingMetadata = metadataDao.getMetadata(filePath)
                val file = File(filePath)
                
                if (!forceRescan && existingMetadata != null && 
                    existingMetadata.lastModified == file.lastModified()) {
                    Log.d(TAG, "Skipping $filePath - already cached and up to date")
                    continue
                }
                
                val metadata = extractMetadataInfo(filePath)
                metadataDao.insertMetadata(metadata)
                Log.d(TAG, "Scanned and cached metadata for: $filePath")
                
            } catch (e: Exception) {
                Log.e(TAG, "Error scanning file: $filePath", e)
                // Insert error metadata
                val errorMetadata = MetadataInfo(
                    filePath = filePath,
                    fileName = File(filePath).name,
                    hasErrors = true,
                    errorMessage = e.message
                )
                metadataDao.insertMetadata(errorMetadata)
            }
        }
    }
    
    private suspend fun scanAllMusicFiles(
        repository: MusicRepository, 
        metadataDao: MetadataDao, 
        forceRescan: Boolean
    ) {
        try {
            Log.d(TAG, "Starting full music library metadata scan")
            
            // Get all songs from repository (use silent version to avoid LibraryScanTracker notifications)
            val allSongs = repository.getAllSongs()
            Log.d(TAG, "Found ${allSongs.size} songs to scan")
            
            val batch = mutableListOf<MetadataInfo>()
            val batchSize = 10
            
            for ((index, song) in allSongs.withIndex()) {
                try {
                    // Check if we need to scan this file
                    val existingMetadata = metadataDao.getMetadata(song.path)
                    val file = File(song.path)
                    
                    if (!forceRescan && existingMetadata != null && 
                        file.exists() && existingMetadata.lastModified == file.lastModified()) {
                        continue
                    }
                    
                    val metadata = extractMetadataInfo(song.path)
                    batch.add(metadata)
                    
                    // Insert in batches for better performance
                    if (batch.size >= batchSize || index == allSongs.size - 1) {
                        metadataDao.insertAll(batch)
                        Log.d(TAG, "Processed batch of ${batch.size} files (${index + 1}/${allSongs.size})")
                        batch.clear()
                    }
                    
                } catch (e: Exception) {
                    Log.e(TAG, "Error scanning ${song.path}", e)
                    batch.add(MetadataInfo(
                        filePath = song.path,
                        fileName = File(song.path).name,
                        hasErrors = true,
                        errorMessage = e.message
                    ))
                }
            }
            
            Log.d(TAG, "Completed full library metadata scan")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in full library scan", e)
            throw e
        }
    }
    
    private fun extractMetadataInfo(filePath: String): MetadataInfo {
        val file = File(filePath)
        val retriever = MediaMetadataRetriever()
        
        return try {
            if (filePath.startsWith("content://")) {
                retriever.setDataSource(applicationContext, Uri.parse(filePath))
            } else {
                retriever.setDataSource(filePath)
            }
            
            val bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
            val sampleRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull() ?: 0
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val mimeType = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE) ?: ""
            
            // Try to get additional metadata
            val channels = try {
                // Some devices support this
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_NUM_TRACKS)?.toIntOrNull() ?: 0
            } catch (e: Exception) { 0 }
            
            val format = when {
                mimeType.contains("mp3", true) -> "MP3"
                mimeType.contains("flac", true) -> "FLAC"
                mimeType.contains("opus", true) -> "Opus"
                mimeType.contains("ogg", true) -> "OGG"
                mimeType.contains("m4a", true) || mimeType.contains("mp4", true) -> "M4A"
                mimeType.contains("wav", true) -> "WAV"
                mimeType.contains("wma", true) -> "WMA"
                else -> filePath.substringAfterLast('.', "Unknown").uppercase()
            }
            
            val quality = when {
                bitrate >= 320 -> "High (${bitrate / 1000} kbps)"
                bitrate >= 256 -> "Good (${bitrate / 1000} kbps)"
                bitrate >= 128 -> "Standard (${bitrate / 1000} kbps)"
                bitrate > 0 -> "Low (${bitrate / 1000} kbps)"
                format == "FLAC" -> "Lossless"
                else -> "Unknown"
            }
            
            MetadataInfo(
                filePath = filePath,
                fileName = file.name,
                duration = duration,
                bitrate = bitrate,
                sampleRate = sampleRate,
                format = format,
                mimeType = mimeType,
                fileSize = if (file.exists()) file.length() else 0L,
                lastModified = if (file.exists()) file.lastModified() else 0L,
                channels = channels,
                codec = format,
                quality = quality,
                hasErrors = false
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting metadata for $filePath", e)
            throw e
        } finally {
            try {
                retriever.release()
            } catch (e: Exception) {
                Log.w(TAG, "Error releasing MediaMetadataRetriever", e)
            }
        }
    }
}