package com.stash.stashwave.work

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class PostDownloadMoverWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val prefs = applicationContext.getSharedPreferences("settings", 0)
            val enabled = prefs.getBoolean("enable_post_download_mover", false)
            if (!enabled) return@withContext Result.success()

            val srcUriStr = prefs.getString("seal_source_folder_uri", null)
            val dstUriStr = prefs.getString("seal_last_target_folder_uri", null)
            if (srcUriStr.isNullOrBlank() || dstUriStr.isNullOrBlank()) return@withContext Result.success()

            val srcTree = DocumentFile.fromTreeUri(applicationContext, Uri.parse(srcUriStr))
            val dstTree = DocumentFile.fromTreeUri(applicationContext, Uri.parse(dstUriStr))
            if (srcTree == null || !srcTree.exists() || dstTree == null || !dstTree.exists()) {
                return@withContext Result.success()
            }

            var movedCount = 0
            srcTree.listFiles().forEach { file ->
                if (file.isFile && isAudio(file) && !file.name.orEmpty().endsWith(".partial", ignoreCase = true)) {
                    val targetName = file.name ?: "audio_${System.currentTimeMillis()}"
                    // Skip if already exists
                    val existing = dstTree.findFile(targetName)
                    if (existing != null && existing.exists()) return@forEach

                    // Create destination and copy streams
                    val dst = dstTree.createFile(file.type ?: "audio/*", targetName)
                    if (dst != null) {
                        applicationContext.contentResolver.openInputStream(file.uri)?.use { input ->
                            applicationContext.contentResolver.openOutputStream(dst.uri)?.use { output ->
                                input.copyTo(output)
                            }
                        }
                        // Delete source only if copy succeeded
                        try { file.delete() } catch (_: Exception) {}
                        movedCount++
                    }
                }
            }

            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun isAudio(doc: DocumentFile): Boolean {
        val name = doc.name?.lowercase() ?: return false
        val audioExt = setOf("mp3","opus","ogg","oga","flac","m4a","aac","wav","wma","mka")
        val ext = name.substringAfterLast('.', "")
        return ext in audioExt || (doc.type?.startsWith("audio/") == true)
    }
}