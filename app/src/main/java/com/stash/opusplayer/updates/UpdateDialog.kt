package com.stash.opusplayer.updates

import android.app.Dialog
import android.content.Context
import android.view.LayoutInflater
import android.view.View
import androidx.core.content.ContextCompat
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.stash.opusplayer.R
import com.stash.opusplayer.data.UpdateInfo
import com.stash.opusplayer.data.UpdatePriority
import com.stash.opusplayer.databinding.DialogUpdateAvailableBinding

class UpdateDialog(
    private val context: Context,
    private val updateInfo: UpdateInfo,
    private val notificationStrategy: NotificationStrategy,
    private val onUpdateClick: (UpdateInfo) -> Unit,
    private val onSkipClick: (UpdateInfo) -> Unit,
    private val onLaterClick: (UpdateInfo) -> Unit
) {
    
    private lateinit var binding: DialogUpdateAvailableBinding
    private lateinit var dialog: Dialog
    
    fun create(): Dialog {
        binding = DialogUpdateAvailableBinding.inflate(LayoutInflater.from(context))
        
        setupUI()
        setupClickListeners()
        
        val dialogBuilder = MaterialAlertDialogBuilder(context, R.style.UpdateDialogTheme)
            .setView(binding.root)
            .setCancelable(!updateInfo.isForced) // Force updates can't be canceled
        
        dialog = dialogBuilder.create()
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        
        return dialog
    }
    
    private fun setupUI() {
        binding.apply {
            // Update title and version
            updateTitle.text = when {
                updateInfo.isForced -> "Critical Update Required"
                updateInfo.isCritical -> "Important Update Available"
                else -> "Update Available"
            }
            
            updateVersion.text = "Version ${updateInfo.latestVersion}"
            
            // Set priority badge
            setupPriorityBadge()
            
            // Update info
            releaseDate.text = updateInfo.formattedPublishedDate
            fileSize.text = updateInfo.fileSize
            
            // Release notes
            releaseNotes.text = formatReleaseNotes(updateInfo.formattedReleaseNotes)
            
            // AI recommendation
            setupAIRecommendation()
            
            // Button configuration based on update type
            setupButtons()
        }
    }
    
    private fun setupPriorityBadge() {
        binding.priorityBadge.apply {
            when (updateInfo.updatePriority) {
                UpdatePriority.CRITICAL -> {
                    text = "CRITICAL"
                    setBackgroundColor(ContextCompat.getColor(context, R.color.error_color))
                    visibility = View.VISIBLE
                }
                UpdatePriority.HIGH -> {
                    text = "IMPORTANT"
                    setBackgroundColor(ContextCompat.getColor(context, R.color.warning_color))
                    visibility = View.VISIBLE
                }
                UpdatePriority.MEDIUM -> {
                    text = "RECOMMENDED"
                    setBackgroundColor(ContextCompat.getColor(context, R.color.primary_color))
                    visibility = View.VISIBLE
                }
                else -> visibility = View.GONE
            }
        }
    }
    
    private fun setupAIRecommendation() {
        val aiText = when (notificationStrategy) {
            NotificationStrategy.URGENT -> "AI strongly recommends installing this update immediately"
            NotificationStrategy.PROMINENT -> "AI recommends this update based on your usage patterns"
            NotificationStrategy.STANDARD -> "AI suggests considering this update when convenient"
            NotificationStrategy.SUBTLE -> "AI notes this update is available but not urgent for your usage"
        }
        
        binding.aiRecommendationText.text = aiText
        
        // Show/hide AI recommendation based on strategy
        binding.aiRecommendation.visibility = when (notificationStrategy) {
            NotificationStrategy.SUBTLE -> View.GONE
            else -> View.VISIBLE
        }
    }
    
    private fun setupButtons() {
        binding.apply {
            when {
                updateInfo.isForced -> {
                    btnSkip.visibility = View.GONE
                    btnLater.visibility = View.GONE
                    btnDownload.text = "Update Now"
                }
                updateInfo.isCritical -> {
                    btnSkip.text = "Risk It"
                    btnLater.text = "Remind Me"
                    btnDownload.text = "Update Now"
                }
                else -> {
                    btnSkip.text = "Skip"
                    btnLater.text = "Later"
                    btnDownload.text = "Update"
                }
            }
            
            // Highlight download button for important updates
            if (updateInfo.updatePriority >= UpdatePriority.HIGH) {
                btnDownload.apply {
                    setBackgroundColor(ContextCompat.getColor(context, R.color.success_color))
                    startAnimation(android.view.animation.AnimationUtils.loadAnimation(
                        context, android.R.anim.fade_in
                    ))
                }
            }
        }
    }
    
    private fun setupClickListeners() {
        binding.apply {
            btnDownload.setOnClickListener {
                dialog.dismiss()
                onUpdateClick(updateInfo)
            }
            
            btnSkip.setOnClickListener {
                dialog.dismiss()
                onSkipClick(updateInfo)
            }
            
            btnLater.setOnClickListener {
                dialog.dismiss()
                onLaterClick(updateInfo)
            }
        }
    }
    
    private fun formatReleaseNotes(notes: String): String {
        // AI-powered formatting for better readability
        return notes
            .split("\n")
            .map { line ->
                when {
                    line.trim().startsWith("-") -> "• ${line.trim().substring(1).trim()}"
                    line.trim().startsWith("*") -> "• ${line.trim().substring(1).trim()}"
                    line.trim().isNotEmpty() && !line.startsWith("•") -> "• $line"
                    else -> line
                }
            }
            .joinToString("\n")
    }
    
    fun show() {
        if (::dialog.isInitialized && !dialog.isShowing) {
            dialog.show()
        }
    }
    
    fun dismiss() {
        if (::dialog.isInitialized && dialog.isShowing) {
            dialog.dismiss()
        }
    }
}

// Custom dialog theme (to be added to themes.xml)
/*
<style name="UpdateDialogTheme" parent="ThemeOverlay.Material3.MaterialAlertDialog">
    <item name="android:windowBackground">@android:color/transparent</item>
    <item name="android:backgroundDimEnabled">true</item>
    <item name="android:backgroundDimAmount">0.6</item>
</style>
*/
