package com.stash.opusplayer.updates

/**
 * User preferences for update checking
 */
data class UpdatePreferences(
    val autoCheckEnabled: Boolean = true,
    val checkFrequency: UpdateFrequency = UpdateFrequency.DAILY,
    val includeBetaUpdates: Boolean = false,
    val notifyForMinorUpdates: Boolean = true,
    val downloadOverWifiOnly: Boolean = true,
    val autoInstallCriticalUpdates: Boolean = false
)

/**
 * Enum for update check frequencies
 */
enum class UpdateFrequency(val hours: Long) {
    NEVER(-1),
    DAILY(24),
    WEEKLY(168),
    MONTHLY(720)
}