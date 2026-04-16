package com.stash.opusplayer.youtube

import android.content.Context
import android.os.Build
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

enum class YouTubePlaybackBackend {
    AUTO,
    YT_DLP,
    LAVALINK
}

data class LavalinkEndpoint(
    val baseUrl: String,
    val password: String,
    val autoConfigured: Boolean
)

object YouTubePlaybackSettings {

    private const val PREFS_NAME = "settings"
    private const val PREF_BACKEND = "youtube_playback_backend"
    private const val PREF_LAVALINK_URL = "youtube_lavalink_url"
    private const val PREF_LAVALINK_PASSWORD = "youtube_lavalink_password"
    private const val PREF_LAVALINK_AUTO_CONFIGURED = "youtube_lavalink_auto_configured"
    private const val DEFAULT_LAVALINK_PORT = 2333
    private const val DEFAULT_LAVALINK_PASSWORD = "youshallnotpass"

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
        prefs(context).edit()
            .putString(PREF_LAVALINK_URL, normalizeBaseUrl(url))
            .putBoolean(PREF_LAVALINK_AUTO_CONFIGURED, false)
            .apply()
    }

    fun getLavalinkPassword(context: Context): String {
        return prefs(context).getString(PREF_LAVALINK_PASSWORD, "").orEmpty().trim()
    }

    fun setLavalinkPassword(context: Context, password: String) {
        prefs(context).edit()
            .putString(PREF_LAVALINK_PASSWORD, password.trim())
            .putBoolean(PREF_LAVALINK_AUTO_CONFIGURED, false)
            .apply()
    }

    fun isAutoConfigured(context: Context): Boolean =
        prefs(context).getBoolean(PREF_LAVALINK_AUTO_CONFIGURED, false)

    fun hasLavalinkConfig(context: Context): Boolean = getLavalinkUrl(context).isNotBlank()

    fun getDefaultPassword(): String = DEFAULT_LAVALINK_PASSWORD

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

    fun getSuggestedUrls(context: Context): List<String> {
        val savedUrl = getLavalinkUrl(context)
        val candidates = linkedSetOf<String>()
        if (savedUrl.isNotBlank()) {
            candidates += savedUrl
        }
        candidates += "http://127.0.0.1:$DEFAULT_LAVALINK_PORT"
        candidates += "http://localhost:$DEFAULT_LAVALINK_PORT"
        if (isLikelyEmulator()) {
            candidates += "http://10.0.2.2:$DEFAULT_LAVALINK_PORT"
        }
        candidates += collectSubnetCandidates()
        return candidates.take(10)
    }

    suspend fun resolveEndpoint(
        context: Context,
        client: OkHttpClient? = null,
        persistAutoDetected: Boolean = true
    ): LavalinkEndpoint? = withContext(Dispatchers.IO) {
        val probeClient = client?.newBuilder()
            ?.connectTimeout(1200, TimeUnit.MILLISECONDS)
            ?.readTimeout(1200, TimeUnit.MILLISECONDS)
            ?.callTimeout(1600, TimeUnit.MILLISECONDS)
            ?.build()
            ?: OkHttpClient.Builder()
                .connectTimeout(1200, TimeUnit.MILLISECONDS)
                .readTimeout(1200, TimeUnit.MILLISECONDS)
                .callTimeout(1600, TimeUnit.MILLISECONDS)
                .build()

        val storedUrl = getLavalinkUrl(context)
        val storedPassword = getLavalinkPassword(context)
        val storedAutoFlag = isAutoConfigured(context)

        validateEndpoint(storedUrl, storedPassword, storedAutoFlag, probeClient)?.let {
            return@withContext it
        }

        if (storedUrl.isNotBlank() && storedPassword.isBlank()) {
            validateEndpoint(storedUrl, DEFAULT_LAVALINK_PASSWORD, storedAutoFlag, probeClient)?.let {
                if (storedAutoFlag) {
                    persistAutoConfiguredEndpoint(context, it)
                }
                return@withContext it
            }
            validateEndpoint(storedUrl, "", storedAutoFlag, probeClient)?.let {
                return@withContext it
            }
        }

        for (candidateUrl in getSuggestedUrls(context)) {
            for (candidatePassword in candidatePasswords(storedPassword)) {
                val endpoint = validateEndpoint(candidateUrl, candidatePassword, true, probeClient) ?: continue
                if (persistAutoDetected) {
                    persistAutoConfiguredEndpoint(context, endpoint)
                }
                return@withContext endpoint
            }
        }

        return@withContext if (storedUrl.isBlank()) {
            null
        } else {
            LavalinkEndpoint(
                baseUrl = storedUrl,
                password = storedPassword,
                autoConfigured = storedAutoFlag
            )
        }
    }

    private fun persistAutoConfiguredEndpoint(context: Context, endpoint: LavalinkEndpoint) {
        prefs(context).edit()
            .putString(PREF_LAVALINK_URL, endpoint.baseUrl)
            .putString(PREF_LAVALINK_PASSWORD, endpoint.password)
            .putBoolean(PREF_LAVALINK_AUTO_CONFIGURED, true)
            .apply()
    }

    private fun validateEndpoint(
        rawUrl: String,
        password: String,
        autoConfigured: Boolean,
        client: OkHttpClient
    ): LavalinkEndpoint? {
        val baseUrl = normalizeBaseUrl(rawUrl)
        if (baseUrl.isBlank()) {
            return null
        }

        val reachable = requestSucceeded(client, "$baseUrl/version") ||
            requestSucceeded(client, "$baseUrl/v4/info", password) ||
            requestSucceeded(client, "$baseUrl/info", password)

        return if (reachable) {
            LavalinkEndpoint(
                baseUrl = baseUrl,
                password = password,
                autoConfigured = autoConfigured
            )
        } else {
            null
        }
    }

    private fun requestSucceeded(client: OkHttpClient, url: String, password: String = ""): Boolean {
        return try {
            val request = Request.Builder()
                .url(url)
                .apply {
                    if (password.isNotBlank()) {
                        header("Authorization", password)
                    }
                }
                .get()
                .build()
            client.newCall(request).execute().use { response ->
                response.isSuccessful
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun candidatePasswords(storedPassword: String): List<String> {
        val candidates = linkedSetOf<String>()
        if (storedPassword.isNotBlank()) {
            candidates += storedPassword
        }
        candidates += DEFAULT_LAVALINK_PASSWORD
        candidates += ""
        return candidates.toList()
    }

    private fun isLikelyEmulator(): Boolean {
        return Build.FINGERPRINT.contains("generic", ignoreCase = true) ||
            Build.MODEL.contains("sdk", ignoreCase = true) ||
            Build.PRODUCT.contains("sdk", ignoreCase = true) ||
            Build.HARDWARE.contains("goldfish", ignoreCase = true) ||
            Build.HARDWARE.contains("ranchu", ignoreCase = true)
    }

    private fun collectSubnetCandidates(): List<String> {
        val candidates = linkedSetOf<String>()
        runCatching {
            val interfaces = NetworkInterface.getNetworkInterfaces()?.let(Collections::list).orEmpty()
            interfaces
                .filter { it.isUp && !it.isLoopback && !it.isVirtual }
                .flatMap { Collections.list(it.inetAddresses) }
                .filterIsInstance<Inet4Address>()
                .forEach { address ->
                    val octets = address.hostAddress?.split('.') ?: return@forEach
                    if (octets.size != 4) return@forEach
                    val prefix = "${octets[0]}.${octets[1]}.${octets[2]}"
                    listOf("1", "2", "10", "50", "100", octets[3]).forEach { host ->
                        candidates += "http://$prefix.$host:$DEFAULT_LAVALINK_PORT"
                    }
                }
        }
        return candidates.toList()
    }
}
