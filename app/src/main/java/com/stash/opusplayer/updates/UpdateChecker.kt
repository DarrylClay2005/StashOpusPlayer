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
            if (!forceCheck && !aiAnalyzer.shouldCheckForUpdates(prefs)) {
                return@withContext UpdateCheckResult.NoCheckNeeded
            }
            
            // Update last check timestamp
            prefs.edit().putLong(PREF_LAST_CHECK, System.currentTimeMillis()).apply()
            
            // Decide between stable-only or include prereleases based on user preference
            val includeBeta = prefs.getBoolean(PREF_BETA_UPDATES, false)

            val release = try {
                if (includeBeta) {
                    // Pick the first non-draft release (may be prerelease)
                    val all = apiService.getAllReleases(
                        GitHubApiService.REPO_OWNER,
                        GitHubApiService.REPO_NAME
                    )
                    if (all.isSuccessful) {
                        all.body()?.firstOrNull { !it.draft }
                    } else null
                } else {
                    val latest = apiService.getLatestRelease(
                        GitHubApiService.REPO_OWNER,
                        GitHubApiService.REPO_NAME
                    )
                    if (latest.isSuccessful) latest.body() else null
                }
            } catch (e: Exception) {
                null
            }

            // Fallback: if above failed or no APK asset, scan all releases for first usable APK
            val chosen = release ?: run {
                val all = apiService.getAllReleases(
                    GitHubApiService.REPO_OWNER,
                    GitHubApiService.REPO_NAME
                )
                if (all.isSuccessful) {
                    all.body()?.firstOrNull { r ->
                        !r.draft && (includeBeta || !r.prerelease) && r.assets.any { it.name.endsWith(".apk") }
                    }
                } else null
            }

            if (chosen == null) {
                return@withContext UpdateCheckResult.Error("Failed to fetch updates: no releases found")
            }

            val currentVersion = BuildConfig.VERSION_NAME

            // Build UpdateInfo using a robust asset selector
            val updateInfo = createUpdateInfoWithBestAsset(chosen, currentVersion)
            val shouldShow = aiAnalyzer.shouldShowUpdateToUser(updateInfo, prefs)

            if (!shouldShow) {
                return@withContext UpdateCheckResult.UpdateAvailableButHidden(updateInfo)
            }

            if (updateInfo.isUpdateAvailable) {
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
            
            val releases = response.body()
            if (response.isSuccessful && releases != null) {
                releases.filter { !it.draft }
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
    
    private fun createUpdateInfoWithBestAsset(release: GitHubRelease, currentVersion: String): UpdateInfo {
        val apk = release.assets.firstOrNull { it.name.endsWith(".apk") && it.name.contains("release", ignoreCase = true) }
            ?: release.assets.firstOrNull { it.name.endsWith(".apk") }
        val fileSize = apk?.fileSizeMB ?: "Unknown"
        val url = apk?.downloadUrl ?: ""
        return UpdateInfo(
            currentVersion = currentVersion,
            latestVersion = release.versionName,
            versionName = release.name,
            releaseNotes = cleanReleaseNotes(release.body),
            downloadUrl = url,
            fileSize = fileSize,
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
            checkFrequency = when (prefs.getLong(PREF_UPDATE_FREQUENCY, FREQUENCY_DAILY)) {
                FREQUENCY_NEVER -> UpdateFrequency.NEVER
                FREQUENCY_WEEKLY -> UpdateFrequency.WEEKLY
                FREQUENCY_MONTHLY -> UpdateFrequency.MONTHLY
                else -> UpdateFrequency.DAILY
            },
            includeBetaUpdates = prefs.getBoolean(PREF_BETA_UPDATES, false),
            notifyForMinorUpdates = prefs.getBoolean("notify_minor_updates", true),
            downloadOverWifiOnly = prefs.getBoolean("download_wifi_only", true),
            autoInstallCriticalUpdates = prefs.getBoolean("auto_install_critical", false)
        )
    }
    
    /**
     * Update user preferences
     */
    fun updatePreferences(preferences: UpdatePreferences) {
        prefs.edit().apply {
            putBoolean(PREF_AUTO_CHECK_ENABLED, preferences.autoCheckEnabled)
            putLong(PREF_UPDATE_FREQUENCY, preferences.checkFrequency.hours)
            putBoolean(PREF_BETA_UPDATES, preferences.includeBetaUpdates)
            putBoolean("notify_minor_updates", preferences.notifyForMinorUpdates)
            putBoolean("download_wifi_only", preferences.downloadOverWifiOnly)
            putBoolean("auto_install_critical", preferences.autoInstallCriticalUpdates)
            apply()
        }
    }
}
