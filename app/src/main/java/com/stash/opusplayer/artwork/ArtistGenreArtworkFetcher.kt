package com.stash.opusplayer.artwork

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.net.URLEncoder
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.TimeUnit

class ArtistGenreArtworkFetcher(private val context: Context) {
    companion object {
        private const val TAG = "ArtistGenreFetcher"

        private fun normalizeName(name: String): String = name
            .lowercase(Locale.getDefault())
            .replace("\u00A0", " ")
            .replace("\n", " ")
            .replace(Regex("\\s+"), " ")
            .trim()

        private fun sha1(text: String): String {
            val md = MessageDigest.getInstance("SHA-1")
            val bytes = md.digest(text.toByteArray())
            return bytes.joinToString("") { String.format("%02x", it) }
        }

        fun artistFile(context: Context, name: String): File {
            val key = sha1(normalizeName(name))
            return File(File(context.cacheDir, "artist_artwork").apply { mkdirs() }, "$key.jpg")
        }

        fun genreFile(context: Context, name: String): File {
            val key = sha1(normalizeName(name))
            return File(File(context.cacheDir, "genre_artwork").apply { mkdirs() }, "$key.jpg")
        }
    }

    private val gson = Gson()
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    private fun prefs() = context.getSharedPreferences("settings", 0)

    suspend fun getOrFetchArtist(name: String): File? = withContext(Dispatchers.IO) {
        val allow = prefs().getBoolean("fetch_artist_images_online", true)
        val out = artistFile(context, name)
        if (out.exists()) return@withContext out
        if (!allow) return@withContext null

        // Try Last.fm if API key exists
        val apiKey = prefs().getString("lastfm_api_key", null)
        if (!apiKey.isNullOrBlank()) {
            try {
                val url = "https://ws.audioscrobbler.com/2.0/?method=artist.getinfo&artist=${enc(name)}&api_key=${enc(apiKey)}&format=json"
                val json = requestJson(url)
                val images = json?.getAsJsonObject("artist")?.getAsJsonArray("image")
                val best = images?.lastOrNull()?.asJsonObject?.get("#text")?.asString
                if (!best.isNullOrBlank()) {
                    requestBytes(best)?.let { bytes ->
                        if (save(out, bytes)) return@withContext out
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Last.fm fetch failed", e)
            }
        }

        // Fallback: Wikipedia page image
        try {
            val json = requestJson("https://en.wikipedia.org/w/api.php?action=query&prop=pageimages&format=json&piprop=thumbnail&pithumbsize=600&redirects=1&titles=${enc(name)}")
            val pages = json?.getAsJsonObject("query")?.getAsJsonObject("pages")
            pages?.entrySet()?.firstOrNull()?.value?.asJsonObject?.getAsJsonObject("thumbnail")?.get("source")?.asString?.let { src ->
                requestBytes(src)?.let { bytes ->
                    if (save(out, bytes)) return@withContext out
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Wikipedia artist fetch failed", e)
        }

        return@withContext null
    }

    suspend fun getOrFetchGenre(name: String): File? = withContext(Dispatchers.IO) {
        val allow = prefs().getBoolean("fetch_genre_images_online", true)
        val out = genreFile(context, name)
        if (out.exists()) return@withContext out
        if (!allow) return@withContext null

        // Wikipedia: try "<Genre> (music)"
        val title = if (name.contains("(music)", true)) name else "$name (music)"
        try {
            val json = requestJson("https://en.wikipedia.org/w/api.php?action=query&prop=pageimages&format=json&piprop=thumbnail&pithumbsize=600&redirects=1&titles=${enc(title)}")
            val pages = json?.getAsJsonObject("query")?.getAsJsonObject("pages")
            pages?.entrySet()?.firstOrNull()?.value?.asJsonObject?.getAsJsonObject("thumbnail")?.get("source")?.asString?.let { src ->
                requestBytes(src)?.let { bytes ->
                    if (save(out, bytes)) return@withContext out
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Wikipedia genre fetch failed", e)
        }
        return@withContext null
    }

    private fun requestJson(url: String): JsonObject? {
        http.newCall(Request.Builder().url(url).build()).execute().use { resp ->
            if (!resp.isSuccessful) return null
            val body = resp.body?.string() ?: return null
            return gson.fromJson(body, JsonObject::class.java)
        }
    }

    private fun requestBytes(url: String): ByteArray? {
        http.newCall(Request.Builder().url(url).build()).execute().use { resp ->
            if (!resp.isSuccessful) return null
            return resp.body?.bytes()
        }
    }

    private fun save(out: File, bytes: ByteArray): Boolean {
        return try {
            out.parentFile?.mkdirs()
            FileOutputStream(out).use { it.write(bytes) }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Save failed: ${out.absolutePath}", e)
            false
        }
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
}

