package com.stash.opusplayer.updates

import com.stash.opusplayer.data.UpdateInfo

/**
 * Sealed class representing different results of update checking
 */
sealed class UpdateCheckResult {
    object NoUpdate : UpdateCheckResult()
    object NoCheckNeeded : UpdateCheckResult()
    data class UpdateAvailable(
        val updateInfo: UpdateInfo,
        val notificationStrategy: NotificationStrategy
    ) : UpdateCheckResult()
    data class UpdateAvailableButHidden(val updateInfo: UpdateInfo) : UpdateCheckResult()
    data class Error(val message: String) : UpdateCheckResult()
}

/**
 * Enum for notification strategies
 */
enum class NotificationStrategy {
    STANDARD,
    LOW_KEY,
    AGGRESSIVE,
    CRITICAL
}

/**
 * Enum for user update decisions
 */
enum class UpdateDecision {
    UPDATED,
    SKIPPED,
    POSTPONED,
    IGNORED
}