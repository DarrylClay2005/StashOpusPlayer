package com.stash.opusplayer.updates

import android.content.Context
import android.content.SharedPreferences
import androidx.preference.PreferenceManager
import com.stash.opusplayer.BuildConfig
import com.stash.opusplayer.data.GitHubRelease
import com.stash.opusplayer.data.UpdateInfo
import com.stash.opusplayer.data.UpdatePriority
import com.stash.opusplayer.network.GitHubApiService
import com.stash.opusplayer.network.NetworkClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Calendar
import java.util.Date
import java.util.concurrent.TimeUnit

class UpdateChecker(private val context: Context) {
    
    private val apiService = NetworkClient.gitHubApiService
    private val prefs = PreferenceManager.getDefaultSharedPreferences(context)
    
    private val aiAnalyzer = UpdateAIAnalyzer()
    
    companion object {
        private const val PREF_LAST_CHECK = "last_update_check"
        private const val PREF_LAST_SKIPPED_VERSION = "last_skipped_version"
        private const val PREF_UPDATE_FREQUENCY = "update_check_frequency"
        private const val PREF_AUTO_CHECK_ENABLED = "auto_update_check"
        private const val PREF_BETA_UPDATES = "include_beta_updates"
        
        // Update check frequencies (in hours)
        private const val FREQUENCY_NEVER = -1L
        private const val FREQUENCY_DAILY = 24L
        private const val FREQUENCY_WEEKLY = 168L
        private const val FREQUENCY_MONTHLY = 720L
    }
    
    /**
     * AI-powered update checking with smart timing and user behavior analysis
     */
    suspend fun checkForUpdates(forceCheck: Boolean = false): UpdateCheckResult = withContext(Dispatchers.IO) {
        try {
            // AI Decision: Should we check for updates now?
            if (!forceCheck && !aiAnalyzer.shouldCheckForUpdates(context, prefs)) {
                return@withContext UpdateCheckResult.NoCheckNeeded
            }
            
            // Update last check timestamp
            prefs.edit().putLong(PREF_LAST_CHECK, System.currentTimeMillis()).apply()
            
            // Fetch latest release from GitHub
            val response = apiService.getLatestRelease(
                GitHubApiService.REPO_OWNER,
                GitHubApiService.REPO_NAME
            )
            
            if (!response.isSuccessful || response.body() == null) {
                return@withContext UpdateCheckResult.Error("Failed to fetch updates: ${response.message()}")
            }
            
            val latestRelease = response.body()!!
            val currentVersion = BuildConfig.VERSION_NAME
            
            // AI Analysis: Determine if this update is worth showing to user
            val updateInfo = createUpdateInfo(latestRelease, currentVersion)
            val shouldShow = aiAnalyzer.shouldShowUpdateToUser(updateInfo, prefs)
            
            if (!shouldShow) {
                return@withContext UpdateCheckResult.UpdateAvailableButHidden(updateInfo)
            }
            
            if (updateInfo.isUpdateAvailable) {
                // AI Enhancement: Customize notification based on user behavior
                val notificationStrategy = aiAnalyzer.getOptimalNotificationStrategy(updateInfo, prefs)
                UpdateCheckResult.UpdateAvailable(updateInfo, notificationStrategy)
            } else {
                UpdateCheckResult.NoUpdate
            }
            
        } catch (e: Exception) {
            UpdateCheckResult.Error("Update check failed: ${e.message}")
        }
    }
    
    /**
     * Get all available releases (for advanced users)
     */
    suspend fun getAllReleases(): List<GitHubRelease> = withContext(Dispatchers.IO) {
        try {
            val response = apiService.getAllReleases(
                GitHubApiService.REPO_OWNER,
                GitHubApiService.REPO_NAME
            )
            
            if (response.isSuccessful && response.body() != null) {
                response.body()!!.filter { !it.draft }
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
    
    private fun createUpdateInfo(release: GitHubRelease, currentVersion: String): UpdateInfo {
        val releaseApk = release.releaseApk
        
        return UpdateInfo(
            currentVersion = currentVersion,
            latestVersion = release.versionName,
            versionName = release.name,
            releaseNotes = cleanReleaseNotes(release.body),
            downloadUrl = releaseApk?.downloadUrl ?: "",
            fileSize = releaseApk?.fileSizeMB ?: "Unknown",
            publishedDate = release.publishedAt,
            isForced = isForceUpdate(release),
            isCritical = isCriticalUpdate(release)
        )
    }
    
    private fun cleanReleaseNotes(body: String): String {
        // AI-powered text cleaning: Remove markdown, format for mobile display
        return body
            .replace(Regex("#+\\s*"), "") // Remove markdown headers
            .replace(Regex("\\*\\*(.*?)\\*\\*"), "$1") // Remove bold formatting
            .replace(Regex("\\*(.*?)\\*"), "$1") // Remove italic formatting
            .replace(Regex("\\[([^\\]]+)\\]\\([^)]+\\)"), "$1") // Remove links, keep text
            .replace(Regex("```[\\s\\S]*?```"), "") // Remove code blocks
            .replace(Regex("\\n\\s*\\n"), "\n") // Remove extra empty lines
            .trim()
    }
    
    private fun isForceUpdate(release: GitHubRelease): Boolean {
        val keywords = listOf("critical", "security", "urgent", "hotfix", "force")
        val content = "${release.name} ${release.body}".lowercase()
        return keywords.any { content.contains(it) }
    }
    
    private fun isCriticalUpdate(release: GitHubRelease): Boolean {
        val keywords = listOf("important", "breaking", "major", "security")
        val content = "${release.name} ${release.body}".lowercase()
        return keywords.any { content.contains(it) }
    }
    
    /**
     * Record user's decision about an update for AI learning
     */
    fun recordUpdateDecision(updateInfo: UpdateInfo, decision: UpdateDecision) {
        prefs.edit().apply {
            putString("last_update_decision", decision.name)
            putLong("last_update_decision_time", System.currentTimeMillis())
            
            if (decision == UpdateDecision.SKIPPED) {
                putString(PREF_LAST_SKIPPED_VERSION, updateInfo.latestVersion)
            }
            
            // Store user behavior for AI analysis
            val behaviorKey = "user_behavior_${decision.name.lowercase()}"
            val currentCount = prefs.getInt(behaviorKey, 0)
            putInt(behaviorKey, currentCount + 1)
            
            apply()
        }
    }
    
    /**
     * Get update checking preferences
     */
    fun getUpdatePreferences(): UpdatePreferences {
        return UpdatePreferences(
            autoCheckEnabled = prefs.getBoolean(PREF_AUTO_CHECK_ENABLED, true),
            checkFrequency = prefs.getLong(PREF_UPDATE_FREQUENCY, FREQUENCY_DAILY),
            includeBetaUpdates = prefs.getBoolean(PREF_BETA_UPDATES, false),
            lastCheckTime = prefs.getLong(PREF_LAST_CHECK, 0)
        )
    }
    
    /**
     * Update user preferences
     */
    fun updatePreferences(preferences: UpdatePreferences) {
        prefs.edit().apply {
            putBoolean(PREF_AUTO_CHECK_ENABLED, preferences.autoCheckEnabled)
            putLong(PREF_UPDATE_FREQUENCY, preferences.checkFrequency)
            putBoolean(PREF_BETA_UPDATES, preferences.includeBetaUpdates)
            apply()
        }
    }
}

sealed class UpdateCheckResult {
    object NoCheckNeeded : UpdateCheckResult()
    object NoUpdate : UpdateCheckResult()
    data class UpdateAvailable(val updateInfo: UpdateInfo, val notificationStrategy: NotificationStrategy) : UpdateCheckResult()
    data class UpdateAvailableButHidden(val updateInfo: UpdateInfo) : UpdateCheckResult()
    data class Error(val message: String) : UpdateCheckResult()
}

enum class UpdateDecision {
    UPDATED, SKIPPED, POSTPONED, IGNORED
}

data class UpdatePreferences(
    val autoCheckEnabled: Boolean,
    val checkFrequency: Long, // in hours
    val includeBetaUpdates: Boolean,
    val lastCheckTime: Long
)

enum class NotificationStrategy {
    SUBTLE, STANDARD, PROMINENT, URGENT
}
