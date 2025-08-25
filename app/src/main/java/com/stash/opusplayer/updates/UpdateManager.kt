package com.stash.opusplayer.updates

import android.app.Activity
import android.content.Context
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import com.stash.opusplayer.data.UpdateInfo
import kotlinx.coroutines.launch
import java.io.File

class UpdateManager(private val context: Context) {
    
    private val updateChecker = UpdateChecker(context)
    private val updateDownloader = UpdateDownloader(context)
    
    /**
     * Check for updates and show notification if available
     */
    fun checkForUpdates(activity: Activity, forceCheck: Boolean = false) {
        if (activity is androidx.lifecycle.LifecycleOwner) {
            activity.lifecycleScope.launch {
                when (val result = updateChecker.checkForUpdates(forceCheck)) {
                    is UpdateCheckResult.UpdateAvailable -> {
                        showUpdateDialog(activity, result.updateInfo, result.notificationStrategy)
                    }
                    is UpdateCheckResult.NoUpdate -> {
                        if (forceCheck) {
                            Toast.makeText(context, "You have the latest version!", Toast.LENGTH_SHORT).show()
                        }
                    }
                    is UpdateCheckResult.Error -> {
                        if (forceCheck) {
                            Toast.makeText(context, "Failed to check for updates: ${result.message}", Toast.LENGTH_LONG).show()
                        }
                    }
                    is UpdateCheckResult.NoCheckNeeded -> {
                        if (forceCheck) {
                            Toast.makeText(context, "Already checked recently", Toast.LENGTH_SHORT).show()
                        }
                    }
                    is UpdateCheckResult.UpdateAvailableButHidden -> {
                        // AI decided not to show this update to user
                        if (forceCheck) {
                            // But show it anyway if user explicitly checked
                            showUpdateDialog(activity, result.updateInfo, NotificationStrategy.STANDARD)
                        }
                    }
                }
            }
        }
    }
    
    private fun showUpdateDialog(
        activity: Activity, 
        updateInfo: UpdateInfo, 
        strategy: NotificationStrategy
    ) {
        val dialog = UpdateDialog(
            context = activity,
            updateInfo = updateInfo,
            notificationStrategy = strategy,
            onUpdateClick = { update ->
                handleUpdateClick(activity, update)
            },
            onSkipClick = { update ->
                handleSkipClick(update)
            },
            onLaterClick = { update ->
                handleLaterClick(update)
            }
        ).create()
        
        dialog.show()
    }
    
    private fun handleUpdateClick(activity: Activity, updateInfo: UpdateInfo) {
        // Record user decision for AI learning
        updateChecker.recordUpdateDecision(updateInfo, UpdateDecision.UPDATED)
        
        // Show download progress dialog
        showDownloadProgressDialog(activity, updateInfo)
        
        // Start download
        if (activity is androidx.lifecycle.LifecycleOwner) {
            activity.lifecycleScope.launch {
                updateDownloader.downloadUpdate(
                    updateInfo = updateInfo,
                    onProgress = { progress ->
                        // Update progress dialog
                        updateDownloadProgress(progress)
                    },
                    onComplete = { file ->
                        dismissProgressDialog()
                        showInstallPrompt(updateInfo, file)
                    },
                    onError = { error ->
                        dismissProgressDialog()
                        Toast.makeText(context, "Download failed: $error", Toast.LENGTH_LONG).show()
                    }
                )
            }
        }
    }
    
    private fun handleSkipClick(updateInfo: UpdateInfo) {
        updateChecker.recordUpdateDecision(updateInfo, UpdateDecision.SKIPPED)
        Toast.makeText(context, "Update skipped", Toast.LENGTH_SHORT).show()
    }
    
    private fun handleLaterClick(updateInfo: UpdateInfo) {
        updateChecker.recordUpdateDecision(updateInfo, UpdateDecision.POSTPONED)
        Toast.makeText(context, "Update postponed", Toast.LENGTH_SHORT).show()
    }
    
    private var progressDialog: androidx.appcompat.app.AlertDialog? = null
    
    private fun showDownloadProgressDialog(activity: Activity, updateInfo: UpdateInfo) {
        val dialogBuilder = androidx.appcompat.app.AlertDialog.Builder(activity)
        val progressBar = android.widget.ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal)
        progressBar.max = 100
        progressBar.progress = 0
        
        val layout = android.widget.LinearLayout(activity).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(50, 50, 50, 50)
            
            addView(android.widget.TextView(activity).apply {
                text = "Downloading Stash Audio v${updateInfo.latestVersion}"
                textSize = 16f
                setPadding(0, 0, 0, 20)
            })
            
            addView(progressBar)
            
            addView(android.widget.TextView(activity).apply {
                id = android.R.id.text1
                text = "0%"
                textSize = 14f
                setPadding(0, 10, 0, 0)
            })
        }
        
        progressDialog = dialogBuilder
            .setTitle("Update Download")
            .setView(layout)
            .setCancelable(false)
            .create()
        
        progressDialog?.show()
    }
    
    private fun updateDownloadProgress(progress: Int) {
        progressDialog?.findViewById<android.widget.ProgressBar>(android.R.id.progress)?.progress = progress
        progressDialog?.findViewById<android.widget.TextView>(android.R.id.text1)?.text = "$progress%"
    }
    
    private fun dismissProgressDialog() {
        progressDialog?.dismiss()
        progressDialog = null
    }
    
    private fun showInstallPrompt(updateInfo: UpdateInfo, updateFile: File) {
        val dialogBuilder = androidx.appcompat.app.AlertDialog.Builder(context)
        
        dialogBuilder
            .setTitle("Update Downloaded")
            .setMessage("Stash Audio v${updateInfo.latestVersion} has been downloaded successfully. Install now?")
            .setPositiveButton("Install") { _, _ ->
                updateDownloader.installUpdate(updateFile)
            }
            .setNegativeButton("Later") { _, _ ->
                // File is saved, user can install later
                Toast.makeText(context, "Update saved. You can install it from notifications.", Toast.LENGTH_LONG).show()
            }
            .setCancelable(false)
            .show()
    }
    
    /**
     * Get update preferences for settings
     */
    fun getUpdatePreferences() = updateChecker.getUpdatePreferences()
    
    /**
     * Update user preferences
     */
    fun updatePreferences(preferences: UpdatePreferences) {
        updateChecker.updatePreferences(preferences)
    }
    
    /**
     * Get all available releases (for advanced users)
     */
    suspend fun getAllReleases() = updateChecker.getAllReleases()
}
