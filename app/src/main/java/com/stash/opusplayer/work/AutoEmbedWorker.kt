package com.stash.opusplayer.work

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Environment
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.utils.FfmpegEmbedder
import com.stash.opusplayer.artwork.ArtworkCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.TimeUnit

class AutoEmbedWorker(appContext: Context, params: WorkerParameters) : CoroutineWorker(appContext, params) {
    companion object {
        private const val TAG = "AutoEmbedWorker"
        private const val PREFS = "auto_embed_worker"
        private const val PREFS_SET = "processed_paths"

        fun schedule(context: Context) {
            val wm = WorkManager.getInstance(context)
            val periodic = PeriodicWorkRequestBuilder<AutoEmbedWorker>(15, TimeUnit.MINUTES)
                .build()
            wm.enqueueUniquePeriodicWork("auto-embed-artwork", ExistingPeriodicWorkPolicy.UPDATE, periodic)

            val once = OneTimeWorkRequestBuilder<AutoEmbedWorker>().build()
            wm.enqueue(once)
        }
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val candidates = collectRecentAudioFiles()
            if (candidates.isEmpty()) return@withContext Result.success()

            val prefs = applicationContext.getSharedPreferences(PREFS, 0)
            val processed = prefs.getStringSet(PREFS_SET, emptySet())?.toMutableSet() ?: mutableSetOf()

            var embeddedCount = 0
            for (file in candidates) {
                if (processed.contains(file.absolutePath)) continue
                try {
                    if (hasEmbeddedArt(file)) {
                        processed.add(file.absolutePath)
                        continue
                    }
                    val title = file.nameWithoutExtension
                    val artBytes = findArtworkBytesByTitle(title)
                    if (artBytes != null) {
                        val ok = if (FfmpegEmbedder.isAvailable()) {
                            FfmpegEmbedder.embedArtwork(applicationContext, file.absolutePath, artBytes)
                        } else {
                            // Fallback to TagEditor
                            val ext = file.extension.lowercase()
                            if (ext == "mp3") {
                                com.stash.opusplayer.utils.TagEditor.embedArtworkMp3(applicationContext, file.absolutePath, artBytes)
                            } else {
                                com.stash.opusplayer.utils.TagEditor.embedArtworkAny(applicationContext, file.absolutePath, artBytes)
                            }
                        }
                        if (ok) {
                            embeddedCount++
                            processed.add(file.absolutePath)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed processing ${file.absolutePath}", e)
                }
            }

            prefs.edit().putStringSet(PREFS_SET, processed).apply()
            Log.i(TAG, "Auto-embed done. Updated $embeddedCount files out of ${candidates.size}")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Worker failure", e)
            Result.failure()
        }
    }

    private fun collectRecentAudioFiles(): List<File> {
        val dirs = listOfNotNull(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        )
        val exts = setOf("mp3", "m4a", "mp4", "aac", "opus", "ogg")
        val now = System.currentTimeMillis()
        val recentMs = TimeUnit.HOURS.toMillis(24)
        val out = mutableListOf<File>()
        dirs.filter { it != null && it.exists() && it.isDirectory }.forEach { root ->
            scanDir(root, exts, now, recentMs, depth = 0, out = out)
        }
        return out
    }

    private fun scanDir(dir: File, exts: Set<String>, now: Long, recentMs: Long, depth: Int, out: MutableList<File>) {
        if (depth > 3) return
        val files = dir.listFiles() ?: return
        for (f in files) {
            if (f.isDirectory) {
                scanDir(f, exts, now, recentMs, depth + 1, out)
            } else {
                val ext = f.extension.lowercase()
                if (exts.contains(ext) && now - f.lastModified() <= recentMs) {
                    out.add(f)
                }
            }
        }
    }

    private fun hasEmbeddedArt(file: File): Boolean {
        val mmr = MediaMetadataRetriever()
        return try {
            mmr.setDataSource(file.absolutePath)
            mmr.embeddedPicture != null
        } catch (_: Exception) {
            false
        } finally {
            try { mmr.release() } catch (_: Exception) {}
        }
    }

    private fun findArtworkBytesByTitle(title: String): ByteArray? {
        val cache = ArtworkCache(applicationContext)
        // Try title as-is
        loadFromCache(cache, title)?.let { return it }
        // Try after splitting on " - " and taking right part
        if (title.contains(" - ")) {
            val t = title.substringAfter(" - ").trim()
            loadFromCache(cache, t)?.let { return it }
        }
        // Strip bracketed / parenthetical content
        val t2 = title
            .replace(Regex("\\([^)]*\\)"), "")
            .replace(Regex("\\[[^]]*\\]"), "")
            .replace(Regex("\\s+"), " ")
            .trim()
        loadFromCache(cache, t2)?.let { return it }
        return null
    }

    private fun loadFromCache(cache: ArtworkCache, title: String): ByteArray? {
        return try {
            val bmp = cache.loadBitmapByTitleIfPresent(title, 512) ?: return null
            val baos = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 85, baos)
            baos.toByteArray()
        } catch (_: Exception) {
            null
        }
    }
}