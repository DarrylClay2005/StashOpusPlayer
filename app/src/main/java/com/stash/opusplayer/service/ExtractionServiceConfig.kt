package com.stash.opusplayer.service

import android.content.Context
import android.util.Log
import com.stash.opusplayer.utils.NetworkUtils
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

/**
 * Preference-backed configuration for optional external extraction services.
 *
 * The original implementation was hard-wired to one local network IP and treated
 * settings as compile-time constants. This version keeps the same discovery
 * behavior, but lets the running app persist real user choices.
 */
object ExtractionServiceConfig {

    private const val TAG = "ExtractionService"
    private const val PREFS_NAME = "settings"
    private const val PREF_AUTO_DETECT_ENABLED = "download_service_auto_detect"
    private const val PREF_MANUAL_SERVICE_URL = "manual_extraction_service_url"
    private const val PREF_SELECTED_SERVICE_URL = "selected_extraction_service_url"

    // Defaults used when the user has not configured anything yet.
    const val AUTO_DETECT_ENABLED = true
    const val PREFERRED_SERVICE_PORT = 8083
    const val FALLBACK_SERVICE_PORT = 8082
    const val LOCAL_SERVICE_ENABLED = true

    // Direct YouTube extraction (fallback)
    const val DIRECT_EXTRACTION_ENABLED = true

    // Cobra API configuration - Open source YouTube downloader
    const val COBRA_API_URL = "https://co.wuk.sh/api/json"
    const val COBRA_ENABLED = false

    // yt-dlp API service configuration
    const val YOUTUBE_DL_API_URL = "https://ytdl-api.onrender.com/api/yt-dlp"
    const val YOUTUBE_DL_ENABLED = false

    // Invidious instance configuration - Privacy-focused YouTube frontend
    const val INVIDIOUS_INSTANCE_URL = "https://invidious.io/api/v1/videos"
    const val INVIDIOUS_ENABLED = false

    // Alternative services (disabled by default - enable if you have access)
    const val ALTERNATIVE_SERVICE_1_URL = "https://your-custom-service.com/extract"
    const val ALTERNATIVE_SERVICE_1_ENABLED = false

    const val ALTERNATIVE_SERVICE_2_URL = "https://another-service.com/api/youtube"
    const val ALTERNATIVE_SERVICE_2_ENABLED = false

    const val REQUEST_TIMEOUT_MS = 30000L
    const val CONNECT_TIMEOUT_MS = 10000L

    const val STATIC_SERVICE_URL = "http://127.0.0.1:$PREFERRED_SERVICE_PORT/quick"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isAutoDetectEnabled(context: Context? = null): Boolean {
        return context?.let { prefs(it).getBoolean(PREF_AUTO_DETECT_ENABLED, AUTO_DETECT_ENABLED) }
            ?: AUTO_DETECT_ENABLED
    }

    fun setAutoDetectEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(PREF_AUTO_DETECT_ENABLED, enabled).apply()
    }

    fun getManualServiceUrl(context: Context? = null): String {
        val raw = context?.let { prefs(it).getString(PREF_MANUAL_SERVICE_URL, "") }.orEmpty()
        return normalizeServiceUrl(raw)
    }

    fun setManualServiceUrl(context: Context, serviceUrl: String) {
        val normalized = normalizeServiceUrl(serviceUrl)
        prefs(context).edit().putString(PREF_MANUAL_SERVICE_URL, normalized).apply()
    }

    fun getSelectedServiceUrl(context: Context? = null): String {
        val raw = context?.let { prefs(it).getString(PREF_SELECTED_SERVICE_URL, "") }.orEmpty()
        return normalizeServiceUrl(raw)
    }

    fun setSelectedServiceUrl(context: Context, serviceUrl: String) {
        val normalized = normalizeServiceUrl(serviceUrl)
        prefs(context).edit().putString(PREF_SELECTED_SERVICE_URL, normalized).apply()
    }

    fun normalizeServiceUrl(raw: String): String {
        var url = raw.trim()
        if (url.isBlank()) {
            return ""
        }
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            url = "http://$url"
        }
        url = url.removeSuffix("/")
        return when {
            url.endsWith("/quick") -> url
            url.endsWith("/health") -> "${url.removeSuffix("/health")}/quick"
            url.endsWith("/platforms") -> "${url.removeSuffix("/platforms")}/quick"
            else -> "$url/quick"
        }
    }

    fun buildPlatformsUrl(serviceUrl: String): String =
        normalizeServiceUrl(serviceUrl).replace("/quick", "/platforms")

    fun buildHealthUrl(serviceUrl: String): String =
        normalizeServiceUrl(serviceUrl).replace("/quick", "/health")

    fun buildQuickDownloadUrl(serviceUrl: String, mediaUrl: String, format: String, quality: String): String {
        val normalizedServiceUrl = normalizeServiceUrl(serviceUrl)
        val encodedMediaUrl = URLEncoder.encode(mediaUrl, StandardCharsets.UTF_8.name())
        val encodedFormat = URLEncoder.encode(format, StandardCharsets.UTF_8.name())
        val encodedQuality = URLEncoder.encode(quality, StandardCharsets.UTF_8.name())
        return "$normalizedServiceUrl/$encodedMediaUrl?format=$encodedFormat&quality=$encodedQuality"
    }

    /**
     * Returns the best currently configured endpoint.
     *
     * Priority:
     * 1. User-selected service from discovery
     * 2. Manual service URL from settings
     * 3. Auto-detected local services
     * 4. Loopback fallback
     */
    fun getServiceUrl(context: Context? = null): String {
        val selectedUrl = getSelectedServiceUrl(context)
        val manualUrl = getManualServiceUrl(context)

        val preferredConfiguredUrl = listOf(selectedUrl, manualUrl)
            .firstOrNull { it.isNotBlank() && isServiceEndpointHealthy(it) }
        if (!preferredConfiguredUrl.isNullOrBlank()) {
            return preferredConfiguredUrl
        }

        if (isAutoDetectEnabled(context) && LOCAL_SERVICE_ENABLED) {
            try {
                val localIp = NetworkUtils.getLocalIpAddress(context)
                val detectedUrls = listOf(
                    "http://$localIp:$PREFERRED_SERVICE_PORT/quick",
                    "http://$localIp:$FALLBACK_SERVICE_PORT/quick"
                )
                detectedUrls.firstOrNull { isServiceEndpointHealthy(it) }?.let { detectedUrl ->
                    Log.i(TAG, "Using auto-detected service: $detectedUrl")
                    return detectedUrl
                }
            } catch (e: Exception) {
                Log.w(TAG, "Service auto-detection failed", e)
            }
        }

        if (manualUrl.isNotBlank()) {
            return manualUrl
        }
        return STATIC_SERVICE_URL
    }

    val LOCAL_SERVICE_URL: String
        get() = getServiceUrl()

    fun discoverServices(context: Context? = null): List<NetworkUtils.ServiceInfo> {
        return try {
            val localIp = NetworkUtils.getLocalIpAddress(context)
            NetworkUtils.findAvailableDownloadServices(localIp)
        } catch (e: Exception) {
            Log.e(TAG, "Service discovery failed: ${e.message}")
            emptyList()
        }
    }

    fun testServiceConnectivity(context: Context? = null): Boolean {
        return isServiceEndpointHealthy(getServiceUrl(context))
    }

    private fun isServiceEndpointHealthy(serviceUrl: String): Boolean {
        val normalized = normalizeServiceUrl(serviceUrl)
        if (normalized.isBlank()) {
            return false
        }
        return try {
            val connection = URL(buildHealthUrl(normalized)).openConnection()
            connection.connectTimeout = CONNECT_TIMEOUT_MS.toInt()
            connection.readTimeout = 5000
            connection.connect()
            true
        } catch (e: Exception) {
            Log.d(TAG, "Service connectivity test failed for $normalized: ${e.message}")
            false
        }
    }
}
