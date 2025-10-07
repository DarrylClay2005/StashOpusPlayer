package com.stash.opusplayer.work

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.utils.LibraryScanTracker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class LibraryRescanWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            LibraryScanTracker.startScan("Rescanning library…")
            val repo = MusicRepository(applicationContext)
            // Trigger MediaStore + SAF scans via repository methods
            repo.getAllSongs() // MediaStore scan
            repo.scanCustomFolders() // SAF custom folders
            LibraryScanTracker.completeScan()
            Result.success()
        } catch (e: Exception) {
            LibraryScanTracker.completeScan()
            Result.retry()
        }
    }
}