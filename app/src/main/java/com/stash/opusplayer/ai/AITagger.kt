package com.stash.opusplayer.ai

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.stash.opusplayer.data.Song
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.Locale
import java.util.concurrent.TimeUnit

class AITagger(private val context: Context) {
    private val TAG = "AITagger"
    private val gson = Gson()
    private val http = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private fun prefs() = context.getSharedPreferences("ai_tagger_cache", 0)
    private fun settings() = context.getSharedPreferences("settings", 0)

    suspend fun enhanceSongs(songs: List<Song>): List<Song> = withContext(Dispatchers.IO) {
        songs.map { enhanceSong(it) }
    }

    suspend fun enhanceSong(song: Song): Song = withContext(Dispatchers.IO) {
        var artist = song.artistName
        var genre = song.genre

        if (artist.equals("Unknown Artist", true) || artist.isBlank()) {
            artist = inferArtist(song).ifBlank { artist }
        }
        if (genre.isBlank() || genre.equals("Unknown", true)) {
            genre = inferGenre(song).ifBlank { genre }
        }
        song.copy(artist = artist, genre = genre)
    }

    private fun inferArtist(song: Song): String {
        // 1) From filename pattern "Artist - Title"
        val fileName = if (song.path.startsWith("content://")) {
            Uri.parse(song.path).lastPathSegment ?: song.displayName
        } else {
            song.path.substringAfterLast('/')
        }
        val candidate = fileName.substringBeforeLast('.')
        if (candidate.contains(" - ")) {
            val left = candidate.substringBefore(" - ").trim()
            if (left.isNotBlank() && !looksLikeTrackNumber(left)) return sanitize(left)
        }
        // 2) From parent folder name
        val parent = if (song.path.startsWith("content://")) song.relativePath.trim('/') else song.path.substringBeforeLast('/', "").substringAfterLast('/')
        if (parent.isNotBlank() && !parent.equals("music", true)) return sanitize(parent)
        return ""
    }

    private fun looksLikeTrackNumber(s: String): Boolean = s.matches(Regex("^\n?0?\n?\n?\n?$")) || s.matches(Regex("^[0-9]{1,2}$"))

    private fun inferGenre(song: Song): String {
        // Heuristic keywords
        val haystack = (song.albumName + " " + song.displayName + " " + song.path).lowercase(Locale.getDefault())
        val rule = when {
            listOf("live", "unplugged").any { haystack.contains(it) } -> "Live"
            listOf("remix", "mix", "club").any { haystack.contains(it) } -> "Dance"
            listOf("lofi", "lo-fi", "chill").any { haystack.contains(it) } -> "Lo-Fi"
            listOf("metal", "hardcore").any { haystack.contains(it) } -> "Metal"
            listOf("hip hop", "hip-hop", "rap").any { haystack.contains(it) } -> "Hip-Hop"
            listOf("jazz").any { haystack.contains(it) } -> "Jazz"
            listOf("classical", "symphony", "concerto").any { haystack.contains(it) } -> "Classical"
            else -> ""
        }
        if (rule.isNotBlank()) return rule
        // Try Last.fm tags if API key present and known artist/title
        val apiKey = settings().getString("lastfm_api_key", null)
        if (!apiKey.isNullOrBlank() && !song.artistName.equals("Unknown Artist", true)) {
            try {
                val tag = fetchLastFmTopTag(apiKey, song.artistName, song.displayName)
                if (!tag.isNullOrBlank()) return tag
            } catch (e: Exception) {
                Log.w(TAG, "Last.fm genre fetch failed", e)
            }
        }
        return ""
    }

    private fun sanitize(s: String): String {
        return s.replace('\u00A0', ' ').replace(Regex("\\s+"), " ").trim()
    }

    private fun fetchLastFmTopTag(apiKey: String, artist: String, track: String): String? {
        val url = "https://ws.audioscrobbler.com/2.0/?method=track.getInfo&api_key=${enc(apiKey)}&artist=${enc(artist)}&track=${enc(track)}&format=json"
        val json = requestJson(url) ?: return null
        val toptags = json.getAsJsonObject("track")?.getAsJsonObject("toptags")?.getAsJsonArray("tag")
        val first = toptags?.firstOrNull()?.asJsonObject?.get("name")?.asString
        return first?.let { normalizeGenreName(it) }
    }

    private fun normalizeGenreName(name: String): String {
        val n = name.lowercase(Locale.getDefault())
        return when {
            n.contains("hip") && n.contains("hop") -> "Hip-Hop"
            n.contains("lo") && n.contains("fi") -> "Lo-Fi"
            n.contains("electro") -> "Electronic"
            n.contains("r&b") || n.contains("rnb") -> "R&B"
            else -> name.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
        }
    }

    private fun requestJson(url: String): JsonObject? {
        http.newCall(Request.Builder().url(url).build()).execute().use { resp ->
            if (!resp.isSuccessful) return null
            val body = resp.body?.string() ?: return null
            return gson.fromJson(body, JsonObject::class.java)
        }
    }

    private fun enc(s: String) = java.net.URLEncoder.encode(s, "UTF-8")
}
