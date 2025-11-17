package com.stash.opusplayer.cloud

import android.content.Context
import com.amplifyframework.core.Amplify
import com.stash.opusplayer.data.database.FavoriteDao
import com.stash.opusplayer.data.database.FavoriteEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import timber.log.Timber
import java.io.File

/**
 * Persists favorites per user to S3 as users/{uid}/favorites.json
 * JSON shape: [{"songId":123,"title":"..","artist":"..","album":"..","path":"..","dateAdded":..}, ...]
 */
object CloudFavoritesRepository {
    private fun keyForUser(userId: String) = "users/$userId/favorites.json"

    private suspend fun getUserIdOrNull(): String? = withContext(Dispatchers.IO) {
        runCatching { Amplify.Auth.currentUser.userId }.getOrNull()
    }

    suspend fun pushFavorites(context: Context, dao: FavoriteDao) = withContext(Dispatchers.IO) {
        val uid = getUserIdOrNull() ?: return@withContext
        try {
            val list = dao.getAllFavoritesOnce()
            val arr = JSONArray()
            list.forEach { fav ->
                val obj = JSONObject()
                obj.put("songId", fav.songId)
                obj.put("title", fav.title)
                obj.put("artist", fav.artist)
                obj.put("album", fav.album)
                obj.put("path", fav.path)
                obj.put("dateAdded", fav.dateAdded)
                arr.put(obj)
            }
            val tmp = File.createTempFile("favorites_", ".json", context.cacheDir)
            tmp.writeText(arr.toString())
            kotlinx.coroutines.suspendCancellableCoroutine<Boolean> { cont ->
                Amplify.Storage.uploadFile(keyForUser(uid), tmp, { _ -> cont.resume(true) {} }, { err ->
                    Timber.w(err, "Upload favorites failed")
                    cont.resume(false) {}
                })
            }
            tmp.delete()
        } catch (e: Exception) {
            Timber.w(e, "pushFavorites error")
        }
    }

    suspend fun pullFavoritesToLocal(context: Context, dao: FavoriteDao) = withContext(Dispatchers.IO) {
        val uid = getUserIdOrNull() ?: return@withContext
        val tmp = File.createTempFile("favorites_dl_", ".json", context.cacheDir)
        try {
            val ok = kotlinx.coroutines.suspendCancellableCoroutine<Boolean> { cont ->
                Amplify.Storage.downloadFile(keyForUser(uid), tmp, { _ -> cont.resume(true) {} }, { err ->
                    Timber.i(err, "No cloud favorites yet; skipping pull")
                    cont.resume(false) {}
                })
            }
            if (!ok) return@withContext
            val text = tmp.readText()
            val arr = JSONArray(text)
            // Merge: clear and reinsert for simplicity
            dao.deleteAllFavorites()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val fav = FavoriteEntity(
                    songId = o.optLong("songId", 0),
                    title = o.optString("title", ""),
                    artist = o.optString("artist", ""),
                    album = o.optString("album", ""),
                    path = o.optString("path", ""),
                    dateAdded = o.optLong("dateAdded", System.currentTimeMillis())
                )
                if (fav.path.isNotBlank()) dao.insertFavorite(fav)
            }
        } catch (e: Exception) {
            Timber.w(e, "pullFavoritesToLocal error")
        } finally { runCatching { tmp.delete() } }
    }
}

/** Lightweight extension to read all favorites once. */
suspend fun FavoriteDao.getAllFavoritesOnce(): List<FavoriteEntity> = withContext(Dispatchers.IO) {
    // Flow is great for UI; for sync we expose a one-shot list via Room query
    // Fallback: reuse existing query by collecting first, if there isn't a direct @Query.
    try {
        // Try a raw query via RoomDatabase (not available here); fallback approach:
        val list = java.util.concurrent.CopyOnWriteArrayList<FavoriteEntity>()
        val latch = java.util.concurrent.CountDownLatch(1)
        val job = kotlinx.coroutines.GlobalScope.launch(Dispatchers.IO) {
            try {
                this@getAllFavoritesOnce.getAllFavorites().collect { items ->
                    list.clear(); list.addAll(items)
                    latch.countDown()
                    cancel()
                }
            } catch (_: Exception) { latch.countDown() }
        }
        latch.await(500, java.util.concurrent.TimeUnit.MILLISECONDS)
        job.cancel()
        list.toList()
    } catch (e: Exception) {
        emptyList()
    }
}
