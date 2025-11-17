package com.stash.opusplayer.player.domain.models

/**
 * Buffer Health Status
 * Represents the health state of audio buffering
 */
enum class BufferHealth {
    /** Buffer is healthy with sufficient data */
    GOOD,
    
    /** Buffer is acceptable but monitoring needed */
    FAIR,
    
    /** Buffer is low and may cause issues */
    POOR,
    
    /** Buffer is critically low, rebuffering likely */
    CRITICAL,
    
    /** Buffer state unknown or not initialized */
    UNKNOWN
}
