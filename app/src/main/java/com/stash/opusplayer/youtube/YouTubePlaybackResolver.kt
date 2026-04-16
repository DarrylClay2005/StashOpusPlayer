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
                val lavalinkResult = resolveWithLavalink(video)
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

    private suspend fun resolveWithLavalink(video: YouTubeVideo): Result<ResolvedPlayback> {
        return try {
            val endpoint = YouTubePlaybackSettings.resolveEndpoint(context, client)
                ?: return Result.failure(
                    IllegalStateException(
                        "No Lavalink node was configured or auto-detected. Add one in Streaming settings or keep playback on Auto."
                    )
                )

            val body = requestLoadTracks(endpoint, video.formattedUrl)
                ?: return Result.failure(
                    IllegalStateException(
                        "A Lavalink node was found at ${endpoint.baseUrl}, but it did not return playable track data for this URL."
                    )
                )

            val json = JSONObject(body)
            val streamUrl = extractPlayableUrl(json)
            if (streamUrl.isNullOrBlank()) {
                Result.failure(
                    IllegalStateException(
                        "Lavalink responded without a device-playable stream URL. Use a proxy-capable node or switch playback to Auto."
                    )
                )
            } else {
                Result.success(
                    ResolvedPlayback(
                        streamUrl = streamUrl,
                        sourceLabel = if (endpoint.autoConfigured) "Lavalink auto" else "Lavalink"
                    )
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Lavalink resolution failed", e)
            Result.failure(e)
        }
    }

    private fun requestLoadTracks(endpoint: LavalinkEndpoint, mediaUrl: String): String? {
        val identifier = URLEncoder.encode(mediaUrl, StandardCharsets.UTF_8.name())
        val candidates = listOf(
            "${endpoint.baseUrl}/v4/loadtracks?identifier=$identifier",
            "${endpoint.baseUrl}/loadtracks?identifier=$identifier"
        )

        for (candidate in candidates) {
            val request = Request.Builder()
                .url(candidate)
                .apply {
                    if (endpoint.password.isNotBlank()) {
                        header("Authorization", endpoint.password)
                    }
                }
                .get()
                .build()

            try {
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        Log.w(TAG, "Lavalink loadtracks failed for $candidate with ${response.code}")
                        return@use
                    }
                    return response.body?.string().orEmpty()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error calling Lavalink candidate $candidate", e)
            }
        }

        return null
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
