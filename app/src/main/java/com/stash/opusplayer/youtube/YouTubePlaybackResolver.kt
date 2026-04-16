package com.stash.opusplayer.youtube

import android.content.Context
import android.util.Log
import com.stash.opusplayer.data.YouTubeVideo
import com.stash.opusplayer.utils.YtDlpExtractor
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject

data class ResolvedPlayback(
    val streamUrl: String,
    val sourceLabel: String
)

class YouTubePlaybackResolver(
    private val context: Context,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
) {

    companion object {
        private const val TAG = "YouTubePlaybackResolver"
    }

    suspend fun resolve(video: YouTubeVideo): Result<ResolvedPlayback> = withContext(Dispatchers.IO) {
        return@withContext when (YouTubePlaybackSettings.getBackend(context)) {
            YouTubePlaybackBackend.YT_DLP -> resolveWithYtDlp(video)
            YouTubePlaybackBackend.LAVALINK -> resolveWithLavalink(video)
            YouTubePlaybackBackend.AUTO -> {
                val lavalinkResult = if (YouTubePlaybackSettings.hasLavalinkConfig(context)) {
                    resolveWithLavalink(video)
                } else {
                    Result.failure(IllegalStateException("No Lavalink server configured"))
                }
                if (lavalinkResult.isSuccess) {
                    lavalinkResult
                } else {
                    resolveWithYtDlp(video)
                }
            }
        }
    }

    private suspend fun resolveWithYtDlp(video: YouTubeVideo): Result<ResolvedPlayback> {
        val extractor = YtDlpExtractor(context)
        val streamUrl = extractor.getBestAudioStreamUrl(video.formattedUrl)
        return if (streamUrl.isNullOrBlank()) {
            Result.failure(IllegalStateException("yt-dlp could not resolve a playable audio stream"))
        } else {
            Result.success(ResolvedPlayback(streamUrl, "yt-dlp"))
        }
    }

    private fun resolveWithLavalink(video: YouTubeVideo): Result<ResolvedPlayback> {
        return try {
            val baseUrl = YouTubePlaybackSettings.getLavalinkUrl(context)
            if (baseUrl.isBlank()) {
                return Result.failure(IllegalStateException("No Lavalink server URL configured"))
            }

            val password = YouTubePlaybackSettings.getLavalinkPassword(context)
            val apiBase = if (baseUrl.endsWith("/v4")) baseUrl else "$baseUrl/v4"
            val identifier = URLEncoder.encode(video.formattedUrl, StandardCharsets.UTF_8.name())
            val request = Request.Builder()
                .url("$apiBase/loadtracks?identifier=$identifier")
                .apply {
                    if (password.isNotBlank()) {
                        header("Authorization", password)
                    }
                }
                .get()
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                return Result.failure(
                    IllegalStateException("Lavalink request failed: ${response.code} ${response.message}")
                )
            }

            val body = response.body?.string().orEmpty()
            val json = JSONObject(body)
            val streamUrl = extractPlayableUrl(json)
            if (streamUrl.isNullOrBlank()) {
                Result.failure(
                    IllegalStateException(
                        "Lavalink did not return a device-playable stream URL. Use a Lavalink-compatible proxy node or switch YouTube playback to Auto."
                    )
                )
            } else {
                Result.success(ResolvedPlayback(streamUrl, "Lavalink"))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Lavalink resolution failed", e)
            Result.failure(e)
        }
    }

    private fun extractPlayableUrl(json: JSONObject): String? {
        val loadType = json.optString("loadType")
        if (loadType.equals("empty", ignoreCase = true) || loadType.equals("error", ignoreCase = true)) {
            return null
        }

        val tracks = mutableListOf<JSONObject>()
        json.optJSONArray("tracks")?.let { array ->
            collectTracks(array, tracks)
        }

        when (val data = json.opt("data")) {
            is JSONObject -> {
                if (data.has("encoded") || data.has("info")) {
                    tracks += data
                }
                data.optJSONArray("tracks")?.let { array ->
                    collectTracks(array, tracks)
                }
            }
            is JSONArray -> collectTracks(data, tracks)
        }

        return tracks
            .asSequence()
            .mapNotNull { extractPlayableUrlFromTrack(it) }
            .firstOrNull()
    }

    private fun collectTracks(array: JSONArray, target: MutableList<JSONObject>) {
        for (i in 0 until array.length()) {
            array.optJSONObject(i)?.let(target::add)
        }
    }

    private fun extractPlayableUrlFromTrack(track: JSONObject): String? {
        val pluginInfo = track.optJSONObject("pluginInfo")
        val candidates = listOf(
            pluginInfo?.optString("streamUrl"),
            pluginInfo?.optString("playbackUrl"),
            pluginInfo?.optString("proxyUrl"),
            pluginInfo?.optString("url"),
            track.optJSONObject("info")?.optString("uri")
        )

        return candidates
            .mapNotNull { it?.trim() }
            .firstOrNull { isPlayableStreamUrl(it) }
    }

    private fun isPlayableStreamUrl(url: String): Boolean {
        if (!(url.startsWith("http://") || url.startsWith("https://"))) {
            return false
        }
        return !url.contains("youtube.com/watch", ignoreCase = true) &&
            !url.contains("youtu.be/", ignoreCase = true)
    }
}
