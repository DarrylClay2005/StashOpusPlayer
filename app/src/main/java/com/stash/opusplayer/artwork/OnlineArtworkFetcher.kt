package com.stash.opusplayer.artwork

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.stash.opusplayer.data.Song
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * ArtworkCache handles deterministic cache file names and simple store/retrieve of images.
 */
class ArtworkCache(private val context: Context) {
    companion object {
        private const val TAG = "ArtworkCache"
    }

    private val dir: File by lazy {
        File(context.cacheDir, "artwork").apply { mkdirs() }
    }

    fun keyFor(song: Song): String {
        // Use normalized artist + title + album to increase hit rate and uniqueness
        val base = listOf(song.artistName, song.displayName, song.albumName)
            .joinToString("|") { normalize(it) }
        return sha1(base)
    }

    fun fileForKey(key: String): File = File(dir, "$key.jpg")

    fun fileFor(song: Song): File = fileForKey(keyFor(song))

    fun exists(song: Song): Boolean = fileFor(song).exists()

    fun saveJpeg(bytes: ByteArray, file: File): Boolean {
        return try {
            FileOutputStream(file).use { it.write(bytes) }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save artwork: ${file.absolutePath}", e)
            false
        }
    }

    fun loadBitmapIfPresent(song: Song, maxDim: Int = 512): Bitmap? {
        val f = fileFor(song)
        if (!f.exists()) return null
        return decodeDownsampled(f, maxDim)
    }

    private fun decodeDownsampled(file: File, reqSize: Int): Bitmap? {
        return try {
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, opts)
            var inSample = 1
            var w = opts.outWidth
            var h = opts.outHeight
            while (w / inSample > reqSize || h / inSample > reqSize) {
                inSample *= 2
            }
            val finalOpts = BitmapFactory.Options().apply {
                inJustDecodeBounds = false
                inSampleSize = if (inSample <= 0) 1 else inSample
                inPreferredConfig = Bitmap.Config.RGB_565
                inDither = true
            }
            BitmapFactory.decodeFile(file.absolutePath, finalOpts)
        } catch (_: Throwable) {
            null
        }
    }

    private fun normalize(s: String): String {
        return s.lowercase(Locale.getDefault())
            .replace("\u00A0", " ") // non-breaking spaces
            .replace("&", "and")
            .replace("\n", " ")
            .replace(Regex("\\s+"), " ")
            .trim()
    }

    private fun sha1(text: String): String {
        val md = MessageDigest.getInstance("SHA-1")
        val bytes = md.digest(text.toByteArray())
        return bytes.joinToString("") { String.format("%02x", it) }
    }
}

/**
 * OnlineArtworkFetcher tries MusicBrainz + Cover Art Archive, and falls back to iTunes.
 * It stores images in the ArtworkCache and returns the cached File on success.
 */
class OnlineArtworkFetcher(context: Context) {
    companion object {
        private const val TAG = "OnlineArtworkFetcher"
    }

    private val gson = Gson()
    private val cache = ArtworkCache(context)

    // Dedicated client with a generic UA
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    suspend fun getOrFetch(song: Song): File? = withContext(Dispatchers.IO) {
        try {
            val cached = cache.fileFor(song)
            if (cached.exists()) return@withContext cached

            com.stash.opusplayer.utils.ImageDownloadTracker.begin()
            try {
                // Try MusicBrainz + CAA
            val mbid = searchMusicBrainzRecording(song)
            if (mbid != null) {
                downloadCoverArtArchive(mbid)?.let { bytes ->
                    if (cache.saveJpeg(bytes, cached)) return@withContext cached
                }
            }

            // Fallback: iTunes artwork
            fetchFromITunes(song)?.let { bytes ->
                if (cache.saveJpeg(bytes, cached)) return@withContext cached
            }
            } finally {
                com.stash.opusplayer.utils.ImageDownloadTracker.end()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Artwork fetch error", e)
        }
        return@withContext null
    }

    private fun buildUserAgent(): String = "StashOpusPlayer/${com.stash.opusplayer.BuildConfig.VERSION_NAME} (Android; +https://github.com/DarrylClay2005/StashOpusPlayer)"

    private fun request(url: String): Request = Request.Builder()
        .url(url)
        .header("User-Agent", buildUserAgent())
        .build()

    private fun requestJson(url: String): JsonObject? {
        http.newCall(request(url)).execute().use { resp ->
            if (!resp.isSuccessful) return null
            val body = resp.body?.string() ?: return null
            return gson.fromJson(body, JsonObject::class.java)
        }
    }

    private fun requestBytes(url: String): ByteArray? {
        http.newCall(request(url)).execute().use { resp ->
            if (!resp.isSuccessful) return null
            return resp.body?.bytes()
        }
    }

    private fun norm(text: String): String {
        var t = text
        // Remove parenthetical info like (feat. ...), (Live), (Remix)
        t = t.replace(Regex("\\((feat\\.|with|remix|live|karaoke|instrumental)[^)]*\\)", RegexOption.IGNORE_CASE), "")
        // Remove brackets info like [Remastered]
        t = t.replace(Regex("\\[(remaster|remastered|live|mono|stereo)[^]]*\\]", RegexOption.IGNORE_CASE), "")
        // Collapse whitespace
        t = t.replace(Regex("\\s+"), " ")
        return t.trim()
    }

    private fun buildMbQuery(song: Song): String {
        val title = norm(song.displayName)
        val artist = song.artistName
        return if (artist.equals("Unknown Artist", ignoreCase = true) || artist.isBlank()) {
            // title only
            "recording:\"$title\""
        } else {
            "recording:\"$title\" AND artist:\"${norm(artist)}\""
        }
    }

    private fun urlEncode(s: String): String = java.net.URLEncoder.encode(s, "UTF-8")

    private fun searchMusicBrainzRecording(song: Song): String? {
        val q = buildMbQuery(song)
        val url = "https://musicbrainz.org/ws/2/recording/?fmt=json&limit=5&query=${urlEncode(q)}"
        val json = requestJson(url) ?: return null
        val recordings = json.getAsJsonArray("recordings") ?: return null
        var best: Pair<String, Int>? = null // mbid to score
        val targetTitle = norm(song.displayName).lowercase(Locale.getDefault())
        val targetArtist = norm(song.artistName).lowercase(Locale.getDefault())
        recordings.forEach { el ->
            val obj = el.asJsonObject
            val title = obj.get("title")?.asString?.let { norm(it).lowercase(Locale.getDefault()) } ?: ""
            val releases = obj.getAsJsonArray("releases")
            val artists = obj.getAsJsonArray("artist-credit")
            val artistName = artists?.firstOrNull()?.asJsonObject?.get("name")?.asString
                ?.let { norm(it).lowercase(Locale.getDefault()) } ?: ""
            val score = scoreMatch(targetTitle, targetArtist, title, artistName)
            val mbid = releases?.firstOrNull()?.asJsonObject?.get("id")?.asString
            if (mbid != null) {
                if (best == null || score > best!!.second) {
                    best = mbid to score
                }
            }
        }
        return best?.first
    }

    private fun scoreMatch(targetTitle: String, targetArtist: String, candTitle: String, candArtist: String): Int {
        var score = 0
        if (candTitle == targetTitle) score += 50 else score += tokenOverlapScore(targetTitle, candTitle)
        if (targetArtist.isNotBlank()) {
            if (candArtist == targetArtist) score += 40 else score += tokenOverlapScore(targetArtist, candArtist)
        }
        return score
    }

    private fun tokenOverlapScore(a: String, b: String): Int {
        val sa = a.split(' ').filter { it.isNotBlank() }.toSet()
        val sb = b.split(' ').filter { it.isNotBlank() }.toSet()
        val inter = sa.intersect(sb).size
        val denom = (sa.size + sb.size).coerceAtLeast(1)
        return (100 * 2 * inter / denom) // scaled approx Jaccard*100
    }

    private fun downloadCoverArtArchive(mbid: String): ByteArray? {
        // Direct image endpoint; let OkHttp follow redirects
        val sizes = listOf(500, 250)
        for (sz in sizes) {
            val url = "https://coverartarchive.org/release/$mbid/front-$sz"
            requestBytes(url)?.let { return it }
        }
        // JSON lookup fallback
        val meta = requestJson("https://coverartarchive.org/release/$mbid")
        val images = meta?.getAsJsonArray("images")
        val front = images?.firstOrNull { it.asJsonObject.get("front")?.asBoolean == true }?.asJsonObject
        val url = front?.get("image")?.asString
        if (!url.isNullOrBlank()) {
            return requestBytes(url)
        }
        return null
    }

    private fun fetchFromITunes(song: Song): ByteArray? {
        val term = buildString {
            if (!song.artistName.equals("Unknown Artist", true)) append(song.artistName).append(' ')
            append(song.displayName)
        }
        val url = "https://itunes.apple.com/search?media=music&entity=song&limit=5&term=${urlEncode(term)}"
        val json = requestJson(url) ?: return null
        val results = json.getAsJsonArray("results") ?: return null
        results.forEach { el ->
            val obj = el.asJsonObject
            val art100 = obj.get("artworkUrl100")?.asString
            if (!art100.isNullOrBlank()) {
                val hi = art100.replace("100x100bb", "600x600bb")
                requestBytes(hi)?.let { return it }
            }
        }
        return null
    }
}

