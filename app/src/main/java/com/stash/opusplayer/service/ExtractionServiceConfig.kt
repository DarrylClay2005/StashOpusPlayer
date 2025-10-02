package com.stash.stashwave.service

import android.content.Context
import com.stash.stashwave.utils.NetworkUtils

/**
 * Configuration for external video/audio extraction services.
 * Users can modify these URLs to use their own hosted services or alternative APIs.
 * Now supports multiple platforms: Vimeo, Bandcamp, Internet Archive, and more!
 * Features auto-detection of local download services.
 */
object ExtractionServiceConfig {
    
    // Auto-detect configuration
    const val AUTO_DETECT_ENABLED = true  // Enable automatic service discovery
    const val PREFERRED_SERVICE_PORT = 8083  // Preferred port for multi-platform service
    const val FALLBACK_SERVICE_PORT = 8082  // Fallback port for YouTube downloader
    
    // Static fallback configuration (used when auto-detect fails)
    private const val FALLBACK_IP = "192.168.12.188"
    const val STATIC_SERVICE_URL = "http://$FALLBACK_IP:$PREFERRED_SERVICE_PORT/quick"
    const val LOCAL_SERVICE_ENABLED = true  // Multi-platform support enabled
    
    // Backup services
    
    // Direct YouTube extraction (fallback)
    const val DIRECT_EXTRACTION_ENABLED = true
    
    // Cobra API configuration - Open source YouTube downloader
    const val COBRA_API_URL = "https://co.wuk.sh/api/json"
    const val COBRA_ENABLED = false  // Disabled - service returning 404
    
    // yt-dlp API service configuration
    const val YOUTUBE_DL_API_URL = "https://ytdl-api.onrender.com/api/yt-dlp"
    const val YOUTUBE_DL_ENABLED = false  // Disabled - service returning 404
    
    // Invidious instance configuration - Privacy-focused YouTube frontend
    const val INVIDIOUS_INSTANCE_URL = "https://invidious.io/api/v1/videos"
    const val INVIDIOUS_ENABLED = false  // Disabled - service returning 404
    
    // Alternative services (disabled by default - enable if you have access)
    const val ALTERNATIVE_SERVICE_1_URL = "https://your-custom-service.com/extract"
    const val ALTERNATIVE_SERVICE_1_ENABLED = false
    
    const val ALTERNATIVE_SERVICE_2_URL = "https://another-service.com/api/youtube"
    const val ALTERNATIVE_SERVICE_2_ENABLED = false
    
    /**
     * Instructions for users who want to set up their own extraction service:
     * 
     * MULTI-PLATFORM SUPPORT:
     * The current service supports multiple platforms:
     * - Vimeo (active)
     * - Bandcamp (active)
     * - Internet Archive (active)
     * - SoundCloud (limited)
     * - Dailymotion (limited)
     * - YouTube (blocked due to anti-bot measures)
     * 
     * Setup steps:
     * 1. Run the multi_platform_downloader.py script on your server
     * 2. Update LOCAL_SERVICE_URL to point to your service
     * 3. Set LOCAL_SERVICE_ENABLED to true
     * 4. Recompile the app
     * 
     * Service endpoints:
     * - /health - Service health check
     * - /platforms - List supported platforms
     * - /quick/<url> - Quick download endpoint
     * - /info/<url> - Get video/audio info
     */
    
    // Timeout settings
    const val REQUEST_TIMEOUT_MS = 30000L
    const val CONNECT_TIMEOUT_MS = 10000L
    
    /**
     * Get the best available download service URL
     * Uses auto-detection if enabled, falls back to static configuration
     */
    fun getServiceUrl(context: Context? = null): String {
        if (!AUTO_DETECT_ENABLED || !LOCAL_SERVICE_ENABLED) {
            return STATIC_SERVICE_URL
        }
        
        return try {
            // Auto-detect local IP
            val localIp = NetworkUtils.getLocalIpAddress(context)
            
            // Check preferred port first (multi-platform service)
            if (NetworkUtils.isServiceReachable(localIp, PREFERRED_SERVICE_PORT, 3000)) {
                val url = "http://$localIp:$PREFERRED_SERVICE_PORT/quick"
                android.util.Log.i("ExtractionService", "Using auto-detected service: $url")
                return url
            }
            
            // Check fallback port (YouTube downloader)
            if (NetworkUtils.isServiceReachable(localIp, FALLBACK_SERVICE_PORT, 3000)) {
                val url = "http://$localIp:$FALLBACK_SERVICE_PORT/quick"
                android.util.Log.i("ExtractionService", "Using fallback service: $url")
                return url
            }
            
            android.util.Log.w("ExtractionService", "Auto-detect failed, using static URL: $STATIC_SERVICE_URL")
            STATIC_SERVICE_URL
        } catch (e: Exception) {
            android.util.Log.e("ExtractionService", "Error in auto-detection: ${e.message}")
            STATIC_SERVICE_URL
        }
    }
    
    /**
     * Get the current service URL (for backward compatibility)
     */
    val LOCAL_SERVICE_URL: String
        get() = getServiceUrl()
    
    /**
     * Discover all available download services on the local network
     */
    fun discoverServices(context: Context? = null): List<NetworkUtils.ServiceInfo> {
        return try {
            val localIp = NetworkUtils.getLocalIpAddress(context)
            NetworkUtils.findAvailableDownloadServices(localIp)
        } catch (e: Exception) {
            android.util.Log.e("ExtractionService", "Service discovery failed: ${e.message}")
            emptyList()
        }
    }
    
    /**
     * Test connectivity to the current service
     */
    fun testServiceConnectivity(context: Context? = null): Boolean {
        val serviceUrl = getServiceUrl(context)
        return try {
            val url = java.net.URL(serviceUrl.replace("/quick", "/health"))
            val connection = url.openConnection()
            connection.connectTimeout = CONNECT_TIMEOUT_MS.toInt()
            connection.readTimeout = 5000
            connection.connect()
            true
        } catch (e: Exception) {
            android.util.Log.w("ExtractionService", "Service connectivity test failed: ${e.message}")
            false
        }
    }
}
