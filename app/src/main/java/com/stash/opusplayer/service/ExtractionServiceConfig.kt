package com.stash.opusplayer.service

/**
 * Configuration for external YouTube extraction services.
 * Users can modify these URLs to use their own hosted services or alternative APIs.
 */
object ExtractionServiceConfig {
    
    // Local yt-dlp Service (using cloned official repository)
    const val LOCAL_SERVICE_URL = "http://192.168.12.186:8080/quick"
    const val LOCAL_SERVICE_ENABLED = true  // Re-enabled to use official yt-dlp
    
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
     * 1. Deploy your own yt-dlp API service (e.g., using Docker)
     * 2. Update the URL constants above to point to your service
     * 3. Set the corresponding _ENABLED flag to true
     * 4. Recompile the app
     * 
     * Example yt-dlp API Docker setup:
     * ```
     * docker run -p 8080:8080 -d --name ytdl-api \
     *   ghcr.io/alexta/ytdl-api:latest
     * ```
     * 
     * Then update YOUTUBE_DL_API_URL to "http://your-server:8080/api/extract"
     */
    
    // Timeout settings
    const val REQUEST_TIMEOUT_MS = 30000L
    const val CONNECT_TIMEOUT_MS = 10000L
}
