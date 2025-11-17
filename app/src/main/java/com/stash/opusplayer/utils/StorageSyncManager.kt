package com.stash.opusplayer.utils

import android.content.Context
import com.amplifyframework.core.Amplify
import com.amplifyframework.storage.StorageException
import com.amplifyframework.storage.options.StorageUploadFileOptions
import com.amplifyframework.storage.result.StorageUploadFileResult
import timber.log.Timber
import java.io.File

object StorageSyncManager {
    // Execute action with current userId if signed in; otherwise no-op
    private fun withCurrentUserId(action: (String) -> Unit) {
        try {
            Amplify.Auth.getCurrentUser(
                { user ->
                    try {
                        action(user.userId)
                    } catch (e: Exception) {
                        Timber.w(e, "Failed running action with userId")
                    }
                },
                { error ->
                    Timber.d(error, "No authenticated user; skipping storage sync")
                }
            )
        } catch (e: Exception) {
            Timber.w(e, "Auth plugin not available; skipping storage sync")
        }
    }

    fun uploadArtworkIfAvailable(context: Context, identifier: String) {
        val path = MetadataStorageManager.getArtworkFilePath(context, identifier) ?: return
        val file = File(path)
        withCurrentUserId { userId ->
            try {
                val key = "users/$userId/artwork/${file.name}"
                Amplify.Storage.uploadFile(
                    key,
                    file,
                    StorageUploadFileOptions.defaultInstance(),
                    { _: StorageUploadFileResult -> Timber.i("Uploaded artwork: $key") },
                    { error: StorageException -> Timber.w(error, "Failed to upload artwork: $key") }
                )
            } catch (e: Exception) {
                Timber.w(e, "Storage plugin not available or not configured; skipping artwork upload")
            }
        }
    }

    fun uploadMetadataIfAvailable(context: Context, identifier: String) {
        val file = File(MetadataFolderHelper.getMetadataJsonPath(context, identifier))
        if (!file.exists()) return
        withCurrentUserId { userId ->
            try {
                val key = "users/$userId/metadata/${file.name}"
                Amplify.Storage.uploadFile(
                    key,
                    file,
                    StorageUploadFileOptions.defaultInstance(),
                    { _: StorageUploadFileResult -> Timber.i("Uploaded metadata: $key") },
                    { error: StorageException -> Timber.w(error, "Failed to upload metadata: $key") }
                )
            } catch (e: Exception) {
                Timber.w(e, "Storage plugin not available or not configured; skipping metadata upload")
            }
        }
    }
}

// Helper to get metadata JSON path consistently
object MetadataFolderHelper {
    fun getMetadataJsonPath(context: Context, identifier: String): String {
        val id = identifier.ifBlank { "unknown" }
        val folder = java.io.File(context.filesDir, "metadata/info")
        val songId = try {
            val md = java.security.MessageDigest.getInstance("SHA-256")
            val hash = md.digest(id.toByteArray())
            hash.joinToString("") { "%02x".format(it) }.take(16)
        } catch (_: Exception) { id.replace(Regex("[^a-zA-Z0-9]"), "_").take(16) }
        return java.io.File(folder, "$songId.json").absolutePath
    }
}
