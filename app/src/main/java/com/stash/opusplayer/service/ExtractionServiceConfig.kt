package com.stash.opusplayer.service

/**
 * Configuration for YouTube extraction using local yt-dlp.
 * 
 * This app now uses built-in yt-dlp and FFmpeg libraries for YouTube audio extraction,
 * eliminating the need for external services. This means the app will work for any user
 * on any IP address without relying on hosted services.
 */
object ExtractionServiceConfig {
    
    /**
     * Local yt-dlp Configuration
     * 
     * The app now uses the youtubedl-android library which bundles yt-dlp and FFmpeg
     * directly into the Android app. This provides:
     * 
     * - Universal compatibility: Works on any device/IP
     * - No external dependencies: Everything runs locally
     * - Better reliability: No network service failures
     * - Privacy: No data sent to third-party services
     * - Offline capability: Works without internet for cached videos
     */
    
    // yt-dlp update configuration
    const val AUTO_UPDATE_YTDLP = true  // Automatically update yt-dlp when possible
    
    // Timeout settings for downloads
    const val REQUEST_TIMEOUT_MS = 60000L  // Increased for large audio files
    const val CONNECT_TIMEOUT_MS = 15000L
    
    /**
     * Audio format preferences for yt-dlp extraction
     * These formats will be tried in order of preference
     */
    val PREFERRED_AUDIO_FORMATS = listOf(
        "bestaudio[ext=m4a]/bestaudio[ext=mp4]",  // Best quality M4A/MP4
        "bestaudio[ext=webm]",                     // WebM audio
        "bestaudio[ext=mp3]",                      // MP3 audio
        "bestaudio"                                 // Fallback to any best audio
    )
    
    /**
     * User agent string for YouTube requests
     * This helps avoid bot detection
     */
    const val USER_AGENT = "Mozilla/5.0 (Android 11; Mobile; rv:68.0) Gecko/68.0 Firefox/88.0"
}
