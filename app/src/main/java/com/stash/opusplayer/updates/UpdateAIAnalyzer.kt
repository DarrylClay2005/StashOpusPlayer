package com.stash.opusplayer.updates

import android.content.Context
import android.content.SharedPreferences
import com.stash.opusplayer.data.UpdateInfo
import com.stash.opusplayer.data.UpdatePriority
import java.util.*
import java.util.concurrent.TimeUnit
import kotlin.math.min

/**
 * AI-powered analyzer for intelligent update checking decisions
 * Uses machine learning-like heuristics to optimize user experience
 */
class UpdateAIAnalyzer {
    
    companion object {
        // AI Learning constants
        private const val SKIP_PENALTY_DECAY = 0.8 // How much skipping affects future notifications
        private const val TIME_FACTOR_WEIGHT = 0.3 // Weight of timing in decisions
        private const val USER_BEHAVIOR_WEIGHT = 0.4 // Weight of past behavior
        private const val UPDATE_IMPORTANCE_WEIGHT = 0.3 // Weight of update importance
        
        // Behavioral analysis thresholds
        private const val FREQUENT_UPDATER_THRESHOLD = 0.7 // 70% update rate = frequent
        private const val SKIP_HAPPY_THRESHOLD = 0.6 // 60% skip rate = skip-happy
        private const val MIN_INTERACTIONS_FOR_ANALYSIS = 3 // Need 3+ interactions for analysis
    }
    
    /**
     * AI Decision: Should we check for updates now?
     * Considers user behavior, timing, and preferences
     */
    fun shouldCheckForUpdates(prefs: SharedPreferences): Boolean {
        val autoCheckEnabled = prefs.getBoolean("auto_update_check", true)
        if (!autoCheckEnabled) return false
        
        val lastCheck = prefs.getLong("last_update_check", 0)
        val frequency = prefs.getLong("update_check_frequency", 24L) // 24 hours default
        
        if (frequency == -1L) return false // Never check
        
        val timeSinceLastCheck = System.currentTimeMillis() - lastCheck
        val frequencyMs = TimeUnit.HOURS.toMillis(frequency)
        
        // AI Enhancement: Adjust frequency based on user behavior
        val behaviorMultiplier = calculateBehaviorMultiplier(prefs)
        val adjustedFrequency = (frequencyMs * behaviorMultiplier).toLong()
        
        // AI Enhancement: Consider optimal timing
        val optimalTimingBonus = getOptimalTimingBonus()
        
        return timeSinceLastCheck >= (adjustedFrequency - (adjustedFrequency * optimalTimingBonus).toLong())
    }
    
    /**
     * AI Decision: Should we show this update to the user?
     * Prevents notification fatigue and respects user preferences
     */
    fun shouldShowUpdateToUser(updateInfo: UpdateInfo, prefs: SharedPreferences): Boolean {
        // Always show critical/forced updates
        if (updateInfo.isForced || updateInfo.isCritical) {
            return true
        }
        
        // Check if user previously skipped this version
        val lastSkippedVersion = prefs.getString("last_skipped_version", "")
        if (lastSkippedVersion == updateInfo.latestVersion) {
            // AI: Only show again if enough time passed or it's more important now
            val skipTime = prefs.getLong("last_update_decision_time", 0)
            val timeSinceSkip = System.currentTimeMillis() - skipTime
            val daysSinceSkip = TimeUnit.MILLISECONDS.toDays(timeSinceSkip)
            
            // Show again after 7 days for regular updates, 3 days for important ones
            val cooldownDays = if (updateInfo.updatePriority >= UpdatePriority.HIGH) 3 else 7
            return daysSinceSkip >= cooldownDays
        }
        
        // AI: Analyze user behavior to determine if they want to see this update
        val userProfile = analyzeUserBehavior(prefs)
        return shouldShowBasedOnProfile(updateInfo, userProfile)
    }
    
    /**
     * AI Enhancement: Get optimal notification strategy based on update and user
     */
    fun getOptimalNotificationStrategy(updateInfo: UpdateInfo, prefs: SharedPreferences): NotificationStrategy {
        val userProfile = analyzeUserBehavior(prefs)
        
        return when {
            updateInfo.isForced -> NotificationStrategy.URGENT
            updateInfo.isCritical -> NotificationStrategy.PROMINENT
            updateInfo.updatePriority >= UpdatePriority.HIGH -> {
                if (userProfile.isFrequentUpdater) NotificationStrategy.STANDARD
                else NotificationStrategy.PROMINENT
            }
            userProfile.isSkipHappy -> NotificationStrategy.SUBTLE
            userProfile.isFrequentUpdater -> NotificationStrategy.STANDARD
            else -> NotificationStrategy.STANDARD
        }
    }
    
    private fun calculateBehaviorMultiplier(prefs: SharedPreferences): Double {
        val totalUpdated = prefs.getInt("user_behavior_updated", 0)
        val totalSkipped = prefs.getInt("user_behavior_skipped", 0)
        val totalInteractions = totalUpdated + totalSkipped
        
        if (totalInteractions < MIN_INTERACTIONS_FOR_ANALYSIS) {
            return 1.0 // Default behavior until we learn more
        }
        
        val updateRate = totalUpdated.toDouble() / totalInteractions
        
        return when {
            updateRate >= FREQUENT_UPDATER_THRESHOLD -> 0.8 // Check less frequently
            updateRate <= (1 - SKIP_HAPPY_THRESHOLD) -> 1.3 // Check more frequently 
            else -> 1.0 // Normal frequency
        }
    }
    
    private fun getOptimalTimingBonus(): Double {
        val calendar = Calendar.getInstance()
        val hour = calendar.get(Calendar.HOUR_OF_DAY)
        val dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
        
        // AI Insight: People are more likely to update during certain times
        val hourBonus = when (hour) {
            in 10..12 -> 0.2 // Late morning
            in 14..16 -> 0.15 // Mid afternoon  
            in 19..21 -> 0.25 // Early evening
            else -> 0.0
        }
        
        val dayBonus = when (dayOfWeek) {
            Calendar.SATURDAY, Calendar.SUNDAY -> 0.1 // Weekends
            else -> 0.0
        }
        
        return min(hourBonus + dayBonus, 0.3) // Cap at 30%
    }
    
    private fun analyzeUserBehavior(prefs: SharedPreferences): UserBehaviorProfile {
        val totalUpdated = prefs.getInt("user_behavior_updated", 0)
        val totalSkipped = prefs.getInt("user_behavior_skipped", 0)
        val totalPostponed = prefs.getInt("user_behavior_postponed", 0)
        val totalIgnored = prefs.getInt("user_behavior_ignored", 0)
        
        val totalInteractions = totalUpdated + totalSkipped + totalPostponed + totalIgnored
        
        if (totalInteractions < MIN_INTERACTIONS_FOR_ANALYSIS) {
            return UserBehaviorProfile() // Default profile
        }
        
        val updateRate = totalUpdated.toDouble() / totalInteractions
        val skipRate = totalSkipped.toDouble() / totalInteractions
        
        return UserBehaviorProfile(
            isFrequentUpdater = updateRate >= FREQUENT_UPDATER_THRESHOLD,
            isSkipHappy = skipRate >= SKIP_HAPPY_THRESHOLD,
            updateRate = updateRate,
            skipRate = skipRate,
            totalInteractions = totalInteractions
        )
    }
    
    private fun shouldShowBasedOnProfile(updateInfo: UpdateInfo, profile: UserBehaviorProfile): Boolean {
        if (profile.totalInteractions < MIN_INTERACTIONS_FOR_ANALYSIS) {
            return true // Show to new users
        }
        
        val baseScore = when (updateInfo.updatePriority) {
            UpdatePriority.LOW -> 0.3
            UpdatePriority.MEDIUM -> 0.6
            UpdatePriority.HIGH -> 0.8
            UpdatePriority.CRITICAL -> 1.0
        }
        
        val behaviorModifier = when {
            profile.isFrequentUpdater -> 0.2
            profile.isSkipHappy -> -0.3
            else -> 0.0
        }
        
        val finalScore = baseScore + behaviorModifier
        
        // AI Decision: Show if score > 0.5
        return finalScore > 0.5
    }
}

/**
 * User behavior profile for AI decision making
 */
data class UserBehaviorProfile(
    val isFrequentUpdater: Boolean = false,
    val isSkipHappy: Boolean = false,
    val updateRate: Double = 0.0,
    val skipRate: Double = 0.0,
    val totalInteractions: Int = 0
) {
    val behaviorType: String
        get() = when {
            isFrequentUpdater -> "Eager Updater"
            isSkipHappy -> "Update Skeptic"
            updateRate > 0.4 -> "Moderate Updater"
            else -> "New User"
        }
}
