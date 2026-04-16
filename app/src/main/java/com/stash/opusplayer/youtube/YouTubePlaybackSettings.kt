package com.stash.opusplayer.youtube

import android.content.Context

enum class YouTubePlaybackBackend {
    AUTO,
    YT_DLP,
    LAVALINK
}

object YouTubePlaybackSettings {

    private const val PREFS_NAME = "settings"
    private const val PREF_BACKEND = "youtube_playback_backend"
    private const val PREF_LAVALINK_URL = "youtube_lavalink_url"
    private const val PREF_LAVALINK_PASSWORD = "youtube_lavalink_password"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun getBackend(context: Context): YouTubePlaybackBackend {
        val raw = prefs(context).getString(PREF_BACKEND, YouTubePlaybackBackend.AUTO.name)
        return try {
            YouTubePlaybackBackend.valueOf(raw ?: YouTubePlaybackBackend.AUTO.name)
        } catch (_: Exception) {
            YouTubePlaybackBackend.AUTO
        }
    }

    fun setBackend(context: Context, backend: YouTubePlaybackBackend) {
        prefs(context).edit().putString(PREF_BACKEND, backend.name).apply()
    }

    fun getLavalinkUrl(context: Context): String {
        val raw = prefs(context).getString(PREF_LAVALINK_URL, "").orEmpty()
        return normalizeBaseUrl(raw)
    }

    fun setLavalinkUrl(context: Context, url: String) {
        prefs(context).edit().putString(PREF_LAVALINK_URL, normalizeBaseUrl(url)).apply()
    }

    fun getLavalinkPassword(context: Context): String {
        return prefs(context).getString(PREF_LAVALINK_PASSWORD, "").orEmpty().trim()
    }

    fun setLavalinkPassword(context: Context, password: String) {
        prefs(context).edit().putString(PREF_LAVALINK_PASSWORD, password.trim()).apply()
    }

    fun hasLavalinkConfig(context: Context): Boolean = getLavalinkUrl(context).isNotBlank()

    fun normalizeBaseUrl(raw: String): String {
        var url = raw.trim()
        if (url.isBlank()) {
            return ""
        }
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            url = "http://$url"
        }
        return url.removeSuffix("/")
    }
}
