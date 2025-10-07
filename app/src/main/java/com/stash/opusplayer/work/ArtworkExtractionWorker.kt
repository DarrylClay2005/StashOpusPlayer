package com.stash.opusplayer.work

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.utils.LibraryScanTracker
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class ArtworkExtractionWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "ArtworkExtractionWorker"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "Starting forced artwork extraction for all audio files")
            LibraryScanTracker.startScan("Re-extracting artwork from all audio files...")
            
            val repo = MusicRepository(applicationContext)
            val metadataExtractor = MetadataExtractor(applicationContext)
            
            // Get all songs from MediaStore and custom folders
            val mediaStoreSongs = repo.getAllSongs()
            val customFolderSongs = repo.scanCustomFolders()
            
            val uniqueSongs = (mediaStoreSongs + customFolderSongs).distinctBy { it.path }
            Log.d(TAG, "Found ${uniqueSongs.size} audio files to process")
            
            var processed = 0
            var artworkExtracted = 0
            
            uniqueSongs.forEach { song ->
                try {
                    LibraryScanTracker.startScan("Processing ${song.displayName} (${processed + 1}/${uniqueSongs.size})")
                    
                    // Force re-extraction of metadata with artwork
                    val enhancedSong = metadataExtractor.extractMetadata(song, forceArtworkExtraction = true)
                    
                    if (!enhancedSong.albumArt.isNullOrEmpty()) {
                        artworkExtracted++
                        Log.d(TAG, "Extracted artwork from: ${song.displayName}")
                    }
                    
                    processed++
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to process ${song.displayName}", e)
                }
            }
            
            LibraryScanTracker.completeScan()
            Log.d(TAG, "Artwork extraction completed. Processed: $processed files, Artwork extracted: $artworkExtracted files")
            
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Artwork extraction worker failed", e)
            LibraryScanTracker.completeScan()
            Result.failure()
        }
    }
}