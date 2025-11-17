package com.stash.opusplayer.cloud

import android.content.Context
import android.net.Uri
import com.amplifyframework.core.Amplify
import com.amplifyframework.storage.options.StorageDownloadFileOptions
import com.amplifyframework.storage.options.StorageUploadFileOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import java.io.File
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

object CloudUserManager {
    suspend fun getUserIdOrNull(): String? = suspendCancellableCoroutine { cont ->
        try {
            Amplify.Auth.getCurrentUser({ user ->
                cont.resume(user.userId)
            }, { _ -> cont.resume(null) })
        } catch (e: Exception) {
            cont.resume(null)
        }
    }

    suspend fun getUsernameOrNull(): String? = suspendCancellableCoroutine { cont ->
        try {
            Amplify.Auth.fetchUserAttributes({ attrs ->
                val name = attrs.firstOrNull { it.key.keyString == "name" }?.value
                cont.resume(name)
            }, { _ -> cont.resume(null) })
        } catch (e: Exception) {
            cont.resume(null)
        }
    }

    suspend fun setUsername(username: String): Boolean = suspendCancellableCoroutine { cont ->
        try {
            val key = com.amplifyframework.auth.AuthUserAttributeKey.name()
            val attr = com.amplifyframework.auth.AuthUserAttribute(key, username)
            Amplify.Auth.updateUserAttribute(attr, { result ->
                cont.resume(result.isUpdated)
            }, { error ->
                Timber.w(error, "Failed to update username")
                cont.resume(false)
            })
        } catch (e: Exception) {
            cont.resume(false)
        }
    }

    suspend fun resetPassword(email: String): Boolean = suspendCancellableCoroutine { cont ->
        try {
            Amplify.Auth.resetPassword(email, { _ -> cont.resume(true) }, { err ->
                Timber.w(err, "Reset password failed")
                cont.resume(false)
            })
        } catch (e: Exception) { cont.resume(false) }
    }

    suspend fun uploadProfilePicture(context: Context, uri: Uri): Boolean = suspendCancellableCoroutine { cont ->
        try {
            val cacheFile = File.createTempFile("avatar_", ".jpg", context.cacheDir)
            context.contentResolver.openInputStream(uri)?.use { ins ->
                cacheFile.outputStream().use { outs -> ins.copyTo(outs) }
            }
            val userId = runCatching { Amplify.Auth.currentUser.userId }.getOrNull()
            if (userId == null) { cont.resume(false); return@suspendCancellableCoroutine }
            val key = "users/$userId/profile/avatar.jpg"
            Amplify.Storage.uploadFile(key, cacheFile, StorageUploadFileOptions.defaultInstance(), { _ ->
                cont.resume(true)
            }, { error ->
                Timber.w(error, "Failed to upload avatar")
                cont.resume(false)
            })
        } catch (e: Exception) {
            Timber.w(e, "uploadProfilePicture error")
            cont.resume(false)
        }
    }

    suspend fun downloadProfilePicture(context: Context): File? = suspendCancellableCoroutine { cont ->
        try {
            val userId = runCatching { Amplify.Auth.currentUser.userId }.getOrNull()
            if (userId == null) { cont.resume(null); return@suspendCancellableCoroutine }
            val key = "users/$userId/profile/avatar.jpg"
            val out = File.createTempFile("avatar_dl_", ".jpg", context.cacheDir)
            Amplify.Storage.downloadFile(key, out, StorageDownloadFileOptions.defaultInstance(), { _ ->
                cont.resume(out)
            }, { error ->
                Timber.i(error, "No profile picture on cloud yet")
                cont.resume(null)
            })
        } catch (e: Exception) {
            cont.resume(null)
        }
    }
}
