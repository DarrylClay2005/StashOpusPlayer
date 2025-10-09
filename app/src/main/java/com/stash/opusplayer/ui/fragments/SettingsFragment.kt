package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import androidx.fragment.app.Fragment
import android.widget.*
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import com.stash.opusplayer.ui.MainActivity
import android.content.Intent
import com.stash.opusplayer.updates.UpdatePreferences
import android.graphics.Color
import android.content.res.ColorStateList
import com.stash.opusplayer.utils.ResponsiveUtils
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class SettingsFragment : Fragment() {
    private val folderPickerLauncher = registerForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        if (uri != null) {
            try {
                // Persist permission to read
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                requireContext().contentResolver.takePersistableUriPermission(
                    uri, flags
                )
                // Save to repository prefs
                val repo = com.stash.opusplayer.data.MusicRepository(requireContext())
                repo.addCustomMusicFolderTreeUri(uri.toString())
                Toast.makeText(requireContext(), "Folder added. Pull-to-refresh Folders tab to rescan.", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(requireContext(), "Failed to add folder", Toast.LENGTH_SHORT).show()
            }
        }
    }

    // Refs for live-updating labels/sliders
    private var volSeekRef: SeekBar? = null
    private var volLabelRef: TextView? = null
    private var cfSeekRef: SeekBar? = null
    private var cfLabelRef: TextView? = null
    private var cfToggleRef: CheckBox? = null
    private var settingsListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null

    // MediaController for applying pitch changes from Settings
    private var mediaController: androidx.media3.session.MediaController? = null
    private var controllerFuture: com.google.common.util.concurrent.ListenableFuture<androidx.media3.session.MediaController>? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        // Root layout with tabs and a content container
        val root = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, 0)
        }

        val tabs = com.google.android.material.tabs.TabLayout(requireContext()).apply {
            addTab(newTab().setText("General"))
            addTab(newTab().setText("Audio"))
            addTab(newTab().setText("Appearance"))
            addTab(newTab().setText("Enhanced")) // New tab for enhanced features
            
            // Apply responsive tab settings
            val tabCount = 4
            tabMode = ResponsiveUtils.getOptimalTabMode(requireContext(), tabCount)
            tabGravity = ResponsiveUtils.getOptimalTabGravity(requireContext(), tabCount)
            
            // Log screen info for debugging
            ResponsiveUtils.logScreenInfo(requireContext())
            
            // Apply responsive text sizing to tabs
            val screenInfo = ResponsiveUtils.getScreenInfo(requireContext())
            if (screenInfo.widthDp < 360) {
                // For very small screens, make tab text smaller
                for (i in 0 until tabCount) {
                    getTabAt(i)?.let { tab ->
                        val tabView = tab.customView ?: tab.view
                        tabView.findViewById<android.widget.TextView>(com.google.android.material.R.id.text)?.let { textView ->
                            ResponsiveUtils.applyResponsiveTextSize(textView, 12f) // Smaller tab text
                        }
                    }
                }
            }
        }
        root.addView(tabs, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        val contentContainer = FrameLayout(requireContext()).apply { id = View.generateViewId() }
        root.addView(contentContainer, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT))

        // Build the four pages as Views
        val generalView = buildGeneralContent()
        val pitchView = buildPitchContent() // Now includes Speed & Reverb too
        val appearanceView = buildAppearanceContent()
        val enhancedView = buildEnhancedFeaturesContent() // New enhanced features page

        // Select initial tab based on arguments
        val initialIndex = arguments?.getInt("initial_tab", 0) ?: 0
        when (initialIndex) {
            1 -> contentContainer.addView(pitchView)
            2 -> contentContainer.addView(appearanceView)
            3 -> contentContainer.addView(enhancedView)
            else -> contentContainer.addView(generalView)
        }
        tabs.getTabAt(initialIndex)?.select()

        tabs.addOnTabSelectedListener(object : com.google.android.material.tabs.TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: com.google.android.material.tabs.TabLayout.Tab) {
                contentContainer.removeAllViews()
                when (tab.position) {
                    0 -> contentContainer.addView(generalView)
                    1 -> contentContainer.addView(pitchView)
                    2 -> contentContainer.addView(appearanceView)
                    3 -> contentContainer.addView(enhancedView)
                }
            }
            override fun onTabUnselected(tab: com.google.android.material.tabs.TabLayout.Tab) {}
            override fun onTabReselected(tab: com.google.android.material.tabs.TabLayout.Tab) {}
        })

        // Connect controller so pitch can be applied live
        connectController()

        return root
    }

    override fun onDestroyView() {
        super.onDestroyView()
        try { mediaController?.release() } catch (_: Exception) {}
        mediaController = null
        controllerFuture?.let { androidx.media3.session.MediaController.releaseFuture(it) }
        controllerFuture = null
        // Unregister settings listener
        try { requireContext().getSharedPreferences("settings", 0).unregisterOnSharedPreferenceChangeListener(settingsListener) } catch (_: Exception) {}
        settingsListener = null
        volSeekRef = null; volLabelRef = null; cfSeekRef = null; cfLabelRef = null; cfToggleRef = null
    }

    private fun restartApp() {
        try {
            val pm = requireContext().packageManager
            val intent = pm.getLaunchIntentForPackage(requireContext().packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                requireActivity().finishAffinity()
            } else {
                // Fallback: restart main activity directly
                startActivity(Intent(requireContext(), MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                requireActivity().finishAffinity()
            }
        } catch (_: Exception) {
            // Best-effort: just recreate
            requireActivity().recreate()
        }
    }

    private fun connectController() {
        try {
val token = androidx.media3.session.SessionToken(requireContext(), android.content.ComponentName(requireContext(), com.stash.opusplayer.service.MusicService::class.java))
            controllerFuture = androidx.media3.session.MediaController.Builder(requireContext(), token).buildAsync()
            controllerFuture?.addListener({
                try { mediaController = controllerFuture?.get() } catch (_: Exception) {}
            }, com.google.common.util.concurrent.MoreExecutors.directExecutor())
        } catch (_: Exception) {}
    }

    private fun buildGeneralContent(): View {
        val scrollView = ScrollView(requireContext())
        val layout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            // Apply responsive padding
            ResponsiveUtils.applyResponsivePadding(this, 16, 16, 16, 16)
        }

        // Title with responsive sizing
        val titleText = TextView(requireContext()).apply {
            text = "Settings"
            ResponsiveUtils.applyResponsiveTextSize(this, 20f)
            ResponsiveUtils.applyResponsivePadding(this, 0, 0, 0, 16)
        }
        layout.addView(titleText)

        // Background Settings Section
        addSectionHeader(layout, "Appearance")

        val backgroundButton = Button(requireContext()).apply {
            text = "Change Background Image"
            setOnClickListener { view ->
                // Add visual feedback
                view.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(100)
                    .withEndAction {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(100)
                            .start()
                    }
                    .start()
                
                Toast.makeText(requireContext(), "Opening image picker...", Toast.LENGTH_SHORT).show()
                (activity as? MainActivity)?.pickBackgroundImage()
            }
        }
        layout.addView(backgroundButton)

        // Default Layouts
        val prefs = requireContext().getSharedPreferences("settings", 0)

        // Default Songs layout
        val songsLabel = TextView(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.default_songs_layout_title)
            setPadding(0, 16, 0, 8)
        }
        layout.addView(songsLabel)
        val songsSpinner = android.widget.Spinner(requireContext())
        val entries = listOf(
            getString(com.stash.opusplayer.R.string.layout_list),
            getString(com.stash.opusplayer.R.string.layout_two_columns),
            getString(com.stash.opusplayer.R.string.layout_three_columns)
        )
        val adapter = android.widget.ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, entries).also {
            it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        }
        songsSpinner.adapter = adapter
        val savedSongsCols = prefs.getInt(com.stash.opusplayer.utils.PrefsKeys.DEFAULT_SONGS_VIEW_COLUMNS, 1)
        songsSpinner.setSelection(when (savedSongsCols) { 1 -> 0; 2 -> 1; else -> 2 })
        songsSpinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: View?, position: Int, id: Long) {
                val cols = when (position) { 0 -> 1; 1 -> 2; else -> 3 }
                prefs.edit().putInt(com.stash.opusplayer.utils.PrefsKeys.DEFAULT_SONGS_VIEW_COLUMNS, cols).apply()
            }
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
        }
        layout.addView(songsSpinner)

        // Default Folder layout (Folder Detail screen)
        val folderLabel = TextView(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.default_folder_layout_title)
            setPadding(0, 16, 0, 8)
        }
        layout.addView(folderLabel)
        val folderSpinner = android.widget.Spinner(requireContext())
        folderSpinner.adapter = adapter
        val savedFolderCols = prefs.getInt(com.stash.opusplayer.utils.PrefsKeys.DEFAULT_FOLDER_DETAIL_VIEW_COLUMNS, 1)
        folderSpinner.setSelection(when (savedFolderCols) { 1 -> 0; 2 -> 1; else -> 2 })
        folderSpinner.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: View?, position: Int, id: Long) {
                val cols = when (position) { 0 -> 1; 1 -> 2; else -> 3 }
                prefs.edit().putInt(com.stash.opusplayer.utils.PrefsKeys.DEFAULT_FOLDER_DETAIL_VIEW_COLUMNS, cols).apply()
            }
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) {}
        }
        layout.addView(folderSpinner)

        // Update Settings Section
        addSectionHeader(layout, "Updates")

        val updateManager = (activity as? MainActivity)?.getUpdateManager()
        val updatePrefs = updateManager?.getUpdatePreferences()

        // Manual check button
        val manualUpdateBtn = Button(requireContext()).apply {
            text = "Check for updates now"
            setOnClickListener {
                try { (activity as? MainActivity)?.getUpdateManager()?.checkForUpdates(requireActivity(), forceCheck = true) } catch (_: Exception) {}
            }
        }
        layout.addView(manualUpdateBtn)

        // Auto-check updates toggle
        val autoCheckToggle = CheckBox(requireContext()).apply {
            text = "Automatically check for updates"
            isChecked = updatePrefs?.autoCheckEnabled ?: true
            setOnCheckedChangeListener { _, isChecked ->
                val updateManagerPrefs = updateManager?.getUpdatePreferences()
                if (updateManagerPrefs != null) {
                    updateManager.updatePreferences(
                        updateManagerPrefs.copy(autoCheckEnabled = isChecked)
                    )
                }
            }
        }
        layout.addView(autoCheckToggle)

        // Album Artwork Section
        addSectionHeader(layout, "Album Artwork")
        val artworkToggle = CheckBox(requireContext()).apply {
            text = "Fetch album art online when missing"
            isChecked = true
            setOnCheckedChangeListener { _, isChecked ->
                val artworkPrefs = requireContext().getSharedPreferences("settings", 0)
                artworkPrefs.edit().putBoolean("fetch_artwork_online", isChecked).apply()
            }
        }
        layout.addView(artworkToggle)

        // Cloud Sync Section
        addSectionHeader(layout, "Cloud Sync")
        
        val cloudSyncService = com.stash.opusplayer.cloud.services.CloudSyncService.getInstance(requireContext())
        
        // Cloud sync enable/disable toggle
        val cloudSyncToggle = CheckBox(requireContext()).apply {
            text = "Enable cloud synchronization"
            isChecked = cloudSyncService.isSyncEnabled()
        }
        layout.addView(cloudSyncToggle)
        
        // Sync status display
        val syncStatusText = TextView(requireContext()).apply {
            text = "Status: ${if (cloudSyncService.isSyncEnabled()) "Enabled" else "Disabled"}"
            textSize = 12f
            setPadding(0, 8, 0, 8)
        }
        layout.addView(syncStatusText)
        
        // AWS Credentials Configuration
        val credentialsButton = Button(requireContext()).apply {
            text = "Configure AWS Credentials"
            setOnClickListener {
                showAWSCredentialsDialog()
            }
        }
        layout.addView(credentialsButton)
        
        // Test Connection Button
        val testConnectionBtn = Button(requireContext()).apply {
            text = "Test Connection"
            setOnClickListener {
                testAWSConnection()
            }
        }
        layout.addView(testConnectionBtn)
        
        // Manual sync button
        val manualSyncBtn = Button(requireContext()).apply {
            text = "Sync Now"
            isEnabled = cloudSyncService.isSyncEnabled()
            setOnClickListener {
                performManualSync()
            }
        }
        layout.addView(manualSyncBtn)
        
        // Cloud sync info
        val syncInfoText = TextView(requireContext()).apply {
            text = "Cloud sync automatically saves your audio settings, listening history, and preferences across all your devices."
            textSize = 11f
            setPadding(0, 8, 0, 16)
        }
        layout.addView(syncInfoText)
        
        // Update sync status when cloud sync toggle changes
        cloudSyncToggle.setOnCheckedChangeListener { _, isChecked ->
            lifecycleScope.launch {
                try {
                    if (isChecked) {
                        val success = cloudSyncService.setSyncEnabled(true)
                        if (!success) {
                            cloudSyncToggle.isChecked = false
                            Toast.makeText(requireContext(), "Failed to enable cloud sync. Check AWS credentials.", Toast.LENGTH_LONG).show()
                        } else {
                            Toast.makeText(requireContext(), "Cloud sync enabled", Toast.LENGTH_SHORT).show()
                        }
                    } else {
                        cloudSyncService.setSyncEnabled(false)
                        Toast.makeText(requireContext(), "Cloud sync disabled", Toast.LENGTH_SHORT).show()
                    }
                    
                    // Update UI elements
                    syncStatusText.text = "Status: ${if (cloudSyncService.isSyncEnabled()) "Enabled" else "Disabled"}"
                    manualSyncBtn.isEnabled = cloudSyncService.isSyncEnabled()
                } catch (e: Exception) {
                    Toast.makeText(requireContext(), "Error: ${e.message}", Toast.LENGTH_LONG).show()
                    cloudSyncToggle.isChecked = false
                    syncStatusText.text = "Status: Error"
                    manualSyncBtn.isEnabled = false
                }
            }
        }


        // Music Folders Section
        addSectionHeader(layout, "Music Folders")
        val addFolderButton = Button(requireContext()).apply {
            text = "Add Folder (tree)"
            setOnClickListener { view ->
                // Add visual feedback
                view.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(100)
                    .withEndAction {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(100)
                            .start()
                    }
                    .start()
                
                Toast.makeText(requireContext(), "Select music folder...", Toast.LENGTH_SHORT).show()
                pickMusicFolder()
            }
        }
        layout.addView(addFolderButton)

        val currentFoldersLabel = TextView(requireContext()).apply {
            text = "Selected folders are used in Folders tab and library scans."
            textSize = 12f
        }
        layout.addView(currentFoldersLabel)

        val manageFoldersButton = Button(requireContext()).apply {
            text = "Manage Folders"
            setOnClickListener { view ->
                // Add visual feedback
                view.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(100)
                    .withEndAction {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(100)
                            .start()
                    }
                    .start()
                
                Toast.makeText(requireContext(), "Loading folder settings...", Toast.LENGTH_SHORT).show()
                showManageFoldersDialog()
            }
        }
        layout.addView(manageFoldersButton)

        val clearCacheButton = Button(requireContext()).apply {
            text = "Clear Artwork Cache"
            setOnClickListener { clearArtworkCache() }
        }
        layout.addView(clearCacheButton)

        val bgRescanToggle = CheckBox(requireContext()).apply {
            text = "Enable background rescans"
            isChecked = true
            setOnCheckedChangeListener { _, isChecked ->
                val bgRescanPrefs = requireContext().getSharedPreferences("settings", 0)
                bgRescanPrefs.edit().putBoolean("enable_background_rescans", isChecked).apply()
                Toast.makeText(requireContext(), if (isChecked) "Background rescans enabled" else "Background rescans disabled", Toast.LENGTH_SHORT).show()
            }
        }
        layout.addView(bgRescanToggle)

        // Check frequency
        val frequencyLabel = TextView(requireContext()).apply {
            text = "Check frequency:"
            setPadding(0, 20, 0, 8)
        }
        layout.addView(frequencyLabel)

        val updateManager2 = (activity as? MainActivity)?.getUpdateManager()
        val updatePrefs2 = updateManager2?.getUpdatePreferences()

        val frequencySpinner = Spinner(requireContext()).apply {
            val frequencies = arrayOf("Daily", "Weekly", "Monthly", "Never")
            val frequencyAdapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, frequencies)
            frequencyAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            this.adapter = frequencyAdapter

            val currentFreq = updatePrefs2?.checkFrequency ?: 24L
            val selectedIndex = when (currentFreq) {
                24L -> 0  // Daily
                168L -> 1 // Weekly
                720L -> 2 // Monthly
                -1L -> 3  // Never
                else -> 0
            }
            setSelection(selectedIndex)

            onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    val frequency = when (position) {
                        0 -> 24L   // Daily
                        1 -> 168L  // Weekly
                        2 -> 720L  // Monthly
                        3 -> -1L   // Never
                        else -> 24L
                    }
                    val updateFreqPrefs = updateManager2?.getUpdatePreferences()
                    if (updateFreqPrefs != null) {
                        val updateFrequency = when (frequency) {
                            24L -> com.stash.opusplayer.updates.UpdateFrequency.DAILY
                            168L -> com.stash.opusplayer.updates.UpdateFrequency.WEEKLY
                            720L -> com.stash.opusplayer.updates.UpdateFrequency.MONTHLY
                            -1L -> com.stash.opusplayer.updates.UpdateFrequency.NEVER
                            else -> com.stash.opusplayer.updates.UpdateFrequency.DAILY
                        }
                        (activity as? MainActivity)?.getUpdateManager()?.updatePreferences(
                            updateFreqPrefs.copy(checkFrequency = updateFrequency)
                        )
                    }
                }
                override fun onNothingSelected(parent: AdapterView<*>?) {}
            }
        }
        layout.addView(frequencySpinner)

        // YouTube API Key Section
        addSectionHeader(layout, "YouTube")
        val apiInfo = TextView(requireContext()).apply {
            text = "Set your YouTube Data API v3 key to enable search and metadata."
            textSize = 12f
        }
        layout.addView(apiInfo)

        val apiKeyInput = EditText(requireContext()).apply {
            hint = "Enter your YouTube API key"
            val apiKeyPrefs = requireContext().getSharedPreferences("settings", 0)
            val existing = apiKeyPrefs.getString("user_youtube_api_key", "") ?: ""
            setText(existing)
        }
        layout.addView(apiKeyInput)

        val saveApiKeyButton = Button(requireContext()).apply {
            text = "Save YouTube API Key"
            setOnClickListener {
                val key = apiKeyInput.text?.toString()?.trim() ?: ""
                val saveKeyPrefs = requireContext().getSharedPreferences("settings", 0)
                saveKeyPrefs.edit().putString("user_youtube_api_key", key).apply()
                // Prompt to reload app so the key takes effect everywhere
                androidx.appcompat.app.AlertDialog.Builder(requireContext())
                    .setTitle("Reload required")
                    .setMessage("The app will reload to apply your YouTube API key. Continue?")
                    .setPositiveButton("Reload") { _, _ -> restartApp() }
                    .setNegativeButton("Later", null)
                    .show()
            }
        }
        layout.addView(saveApiKeyButton)

        // Library Rescan
        val rescanBtn = Button(requireContext()).apply {
            text = "Rescan Library Now"
            setOnClickListener { view ->
                // Add visual feedback
                view.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(100)
                    .withEndAction {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(100)
                            .start()
                    }
                    .start()
                
                // Disable button temporarily to prevent multiple clicks
                view.isEnabled = false
                (view as? Button)?.text = "Starting rescan..."
                
                try {
                    val req = androidx.work.OneTimeWorkRequestBuilder<com.stash.opusplayer.work.LibraryRescanWorker>().build()
                    androidx.work.WorkManager.getInstance(requireContext()).enqueue(req)
                    Toast.makeText(requireContext(), "📚 Library rescan started! Check the banner at top for progress.", Toast.LENGTH_LONG).show()
                } catch (_: Exception) {
                    Toast.makeText(requireContext(), "❌ Failed to start rescan", Toast.LENGTH_LONG).show()
                }
                
                // Re-enable button after delay
                view.postDelayed({
                    view.isEnabled = true
                    (view as? Button)?.text = "Rescan Library Now"
                }, 2000)
            }
        }
        layout.addView(rescanBtn)

        val periodicRescanToggle = CheckBox(requireContext()).apply {
            text = "Enable daily background rescan"
            val periodicPrefs = requireContext().getSharedPreferences("settings", 0)
            isChecked = periodicPrefs.getBoolean("enable_periodic_rescan", false)
            setOnCheckedChangeListener { _, isChecked ->
                periodicPrefs.edit().putBoolean("enable_periodic_rescan", isChecked).apply()
                val wm = androidx.work.WorkManager.getInstance(requireContext())
                val tag = "library_rescan_periodic"
                if (isChecked) {
                    val req = androidx.work.PeriodicWorkRequestBuilder<com.stash.opusplayer.work.LibraryRescanWorker>(java.time.Duration.ofHours(24)).addTag(tag).build()
                    wm.enqueueUniquePeriodicWork(tag, androidx.work.ExistingPeriodicWorkPolicy.UPDATE, req)
                    Toast.makeText(requireContext(), "Periodic rescan scheduled", Toast.LENGTH_SHORT).show()
                } else {
                    wm.cancelAllWorkByTag(tag)
                    Toast.makeText(requireContext(), "Periodic rescan disabled", Toast.LENGTH_SHORT).show()
                }
            }
        }
        layout.addView(periodicRescanToggle)

        // Force Artwork Re-extraction
        val forceArtworkBtn = Button(requireContext()).apply {
            text = "Force Re-extract All Artwork"
            setOnClickListener {
                try {
                    val req = androidx.work.OneTimeWorkRequestBuilder<com.stash.opusplayer.work.ArtworkExtractionWorker>().build()
                    androidx.work.WorkManager.getInstance(requireContext()).enqueue(req)
                    Toast.makeText(requireContext(), "Artwork re-extraction started", Toast.LENGTH_SHORT).show()
                } catch (_: Exception) {
                    Toast.makeText(requireContext(), "Failed to start artwork extraction", Toast.LENGTH_SHORT).show()
                }
            }
        }
        layout.addView(forceArtworkBtn)

        // Manual check button
        val checkUpdateButton = Button(requireContext()).apply {
            text = "Check for Updates Now"
            setPadding(0, 20, 0, 0)
            setOnClickListener {
                (activity as? MainActivity)?.getUpdateManager()?.checkForUpdates(
                    requireActivity(),
                    forceCheck = true
                )
            }
        }
        layout.addView(checkUpdateButton)

        scrollView.addView(layout)
        
        // Apply comprehensive responsive design to the entire layout
        ResponsiveUtils.applyResponsiveDesign(layout)
        
        return scrollView
    }

    private fun buildPitchContent(): View {
        val scrollView = ScrollView(requireContext())
        val layout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            // Apply responsive padding
            ResponsiveUtils.applyResponsivePadding(this, 16, 16, 16, 16)
        }

        val title = TextView(requireContext()).apply {
            text = "Audio Controls"
            ResponsiveUtils.applyResponsiveTextSize(this, 18f)
            ResponsiveUtils.applyResponsivePadding(this, 0, 0, 0, 12)
        }
        layout.addView(title)

        val desc = TextView(requireContext()).apply {
            text = "Adjust global audio: speed, pitch, reverb, and effects presets. Applies live and persists across sessions."
            textSize = 14f
        }
        layout.addView(desc)

        // --- Audio Effects (Equalizer & Presets) ---
        val effectsHeader = TextView(requireContext()).apply {
            text = "Audio Effects"
            textSize = 18f
            setPadding(0, 24, 0, 8)
        }
        layout.addView(effectsHeader)

        // Enable Equalizer & Effects
        val eqEnabledToggle = CheckBox(requireContext()).apply {
            text = "Enable Equalizer & Effects"
            val prefsEq = androidx.preference.PreferenceManager.getDefaultSharedPreferences(requireContext())
            isChecked = prefsEq.getBoolean("equalizer_enabled", false)
            setOnCheckedChangeListener { view, isChecked ->
                // Add haptic feedback
                try {
                    view.performHapticFeedback(android.view.HapticFeedbackConstants.CONTEXT_CLICK)
                } catch (_: Exception) {}
                
                // Persist and apply
                prefsEq.edit().putBoolean("equalizer_enabled", isChecked).apply()
                mediaController?.sendCustomCommand(
                    androidx.media3.session.SessionCommand("SET_EQ_ENABLED", android.os.Bundle.EMPTY),
                    androidx.core.os.bundleOf("enabled" to isChecked)
                )
                Toast.makeText(
                    requireContext(), 
                    if (isChecked) "🎵 Effects enabled - Customize below!" 
                    else "🔇 Effects disabled", 
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
        layout.addView(eqEnabledToggle)

        // Preset selector
        val presetLabel = TextView(requireContext()).apply {
            text = "Preset"
            setPadding(0, 12, 0, 8)
        }
        layout.addView(presetLabel)

        val presetSpinner = Spinner(requireContext())
val presetNames = com.stash.opusplayer.audio.EqualizerPreset.values().map {
            it.name.replace("_", " ").lowercase().replaceFirstChar { c -> c.uppercaseChar() }
        }
        val presetAdapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, presetNames)
        presetAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        presetSpinner.adapter = presetAdapter
        layout.addView(presetSpinner)

        // Restore preset selection
        val prefsEq2 = androidx.preference.PreferenceManager.getDefaultSharedPreferences(requireContext())
val savedPresetName = prefsEq2.getString("equalizer_preset", com.stash.opusplayer.audio.EqualizerPreset.NORMAL.name) ?: com.stash.opusplayer.audio.EqualizerPreset.NORMAL.name
val savedIndex = com.stash.opusplayer.audio.EqualizerPreset.values().indexOfFirst { it.name == savedPresetName }.coerceAtLeast(0)
        presetSpinner.setSelection(savedIndex)

        presetSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
val preset = com.stash.opusplayer.audio.EqualizerPreset.values()[position]
                prefsEq2.edit().putString("equalizer_preset", preset.name).apply()
                mediaController?.sendCustomCommand(
                    androidx.media3.session.SessionCommand("SET_EQ_PRESET", android.os.Bundle.EMPTY),
                    androidx.core.os.bundleOf("preset" to preset.name)
                )
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }

        // Quick preset chips
        val chipGroup = com.google.android.material.chip.ChipGroup(requireContext()).apply {
            isSingleSelection = true
        }
        val quickPresets = listOf(
Pair("3D Surround", com.stash.opusplayer.audio.EqualizerPreset.SURROUND_3D),
            Pair("Concert Hall", com.stash.opusplayer.audio.EqualizerPreset.CONCERT_HALL),
            Pair("Super Bass", com.stash.opusplayer.audio.EqualizerPreset.SUPER_BASS_BOOST),
            Pair("Super Reverb", com.stash.opusplayer.audio.EqualizerPreset.SUPER_REVERB),
            Pair("Lo-Fi", com.stash.opusplayer.audio.EqualizerPreset.LOFI)
        )
        quickPresets.forEach { (label, preset) ->
            val chip = com.google.android.material.chip.Chip(requireContext()).apply {
                text = label
                isCheckable = true
                setOnClickListener {
                    val name = preset.name
presetSpinner.setSelection(com.stash.opusplayer.audio.EqualizerPreset.values().indexOf(preset))
                    prefsEq2.edit().putString("equalizer_preset", name).apply()
                    mediaController?.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_EQ_PRESET", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("preset" to name)
                    )
                    Toast.makeText(requireContext(), "$label preset applied", Toast.LENGTH_SHORT).show()
                }
            }
            chipGroup.addView(chip)
        }
        layout.addView(chipGroup)

        // Bass Boost
        val bassHeader = TextView(requireContext()).apply {
            text = "Bass Boost"
            setPadding(0, 12, 0, 4)
        }
        layout.addView(bassHeader)

        val bassValue = TextView(requireContext()).apply { text = "0%" }
        layout.addView(bassValue)

        val bassSeek = SeekBar(requireContext()).apply {
            max = 1000
            progress = prefsEq2.getInt("bass_boost_strength", 0)
        }
        layout.addView(bassSeek)

        bassSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                bassValue.text = "${progress / 10}%"
                if (fromUser) {
                    prefsEq2.edit().putInt("bass_boost_strength", progress).apply()
                    mediaController?.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_BASS_BOOST", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("strength" to progress)
                    )
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // Virtualizer
        val virtHeader = TextView(requireContext()).apply {
            text = "Virtualizer"
            setPadding(0, 12, 0, 4)
        }
        layout.addView(virtHeader)

        val virtValue = TextView(requireContext()).apply { text = "0%" }
        layout.addView(virtValue)

        val virtSeek = SeekBar(requireContext()).apply {
            max = 1000
            progress = prefsEq2.getInt("virtualizer_strength", 0)
        }
        layout.addView(virtSeek)

        virtSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                virtValue.text = "${progress / 10}%"
                if (fromUser) {
                    prefsEq2.edit().putInt("virtualizer_strength", progress).apply()
                    mediaController?.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_VIRTUALIZER", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("strength" to progress)
                    )
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // More audio effects button
        val moreEffectsBtn = Button(requireContext()).apply {
            text = "More Audio Effects"
            setOnClickListener { view ->
                // Add visual feedback
                view.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(100)
                    .withEndAction {
                        view.animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .setDuration(100)
                            .start()
                    }
                    .start()
                
                Toast.makeText(requireContext(), "Opening advanced equalizer...", Toast.LENGTH_SHORT).show()
                
                try {
                    parentFragmentManager.beginTransaction()
                        .replace((view?.parent as? ViewGroup)?.id ?: (requireActivity() as androidx.appcompat.app.AppCompatActivity).findViewById<View>(com.stash.opusplayer.R.id.main_content).id, com.stash.opusplayer.ui.fragments.EqualizerFragment())
                        .addToBackStack(null)
                        .commit()
                } catch (_: Exception) {
                    // Fallback: just show a toast
                    Toast.makeText(requireContext(), "🎚️ Open Equalizer from the drawer menu for advanced settings.", Toast.LENGTH_LONG).show()
                }
            }
        }
        layout.addView(moreEffectsBtn)

        // --- Playback Enhancements ---
        val enhanceHeader = TextView(requireContext()).apply {
            text = "Playback Enhancements"
            textSize = 18f
            setPadding(0, 24, 0, 8)
        }
        layout.addView(enhanceHeader)

        val settingsPrefs = requireContext().getSharedPreferences("settings", 0)

        // Skip silence toggle
        val skipSilenceToggle = CheckBox(requireContext()).apply {
            text = "Skip silence during playback"
            isChecked = settingsPrefs.getBoolean("skip_silence_enabled", false)
            setOnCheckedChangeListener { _, checked ->
                settingsPrefs.edit().putBoolean("skip_silence_enabled", checked).apply()
            }
        }
        layout.addView(skipSilenceToggle)

        // Gapless / seek accuracy
        val exactSeekToggle = CheckBox(requireContext()).apply {
            text = "Use exact seeks (better for gapless)"
            isChecked = settingsPrefs.getBoolean("exact_seeks", true)
            setOnCheckedChangeListener { _, checked ->
                settingsPrefs.edit().putBoolean("exact_seeks", checked).apply()
            }
        }
        layout.addView(exactSeekToggle)

        // Audio Test: Max Volume
        val audioTestBtn = Button(requireContext()).apply {
            text = "Audio Test: Max Volume"
            setOnClickListener {
                try {
                    // Trigger service to disable all processing and set volume to max
                    mediaController?.sendCustomCommand(
                        androidx.media3.session.SessionCommand("AUDIO_TEST_MAX_VOLUME", android.os.Bundle.EMPTY),
                        android.os.Bundle.EMPTY
                    )
                    // Update local prefs mirrors for immediate UI consistency
                    val sp = requireContext().getSharedPreferences("settings", 0)
                    sp.edit()
                        .putFloat("app_volume", 1.0f)
                        .putBoolean("crossfade_enabled", false)
                        .putLong("crossfade_duration_ms", 0L)
                        .putBoolean("skip_silence_enabled", false)
                        .putBoolean("replaygain_enabled", false)
                        .putInt("reverb_preset", 0)
                        .apply()
                    androidx.preference.PreferenceManager.getDefaultSharedPreferences(requireContext()).edit()
                        .putBoolean("equalizer_enabled", false)
                        .apply()
                    // Update visible controls
                    volSeekRef?.progress = 100
                    cfToggleRef?.isChecked = false
                    cfSeekRef?.apply { isEnabled = false; progress = 0 }
                    android.widget.Toast.makeText(requireContext(), "Set to max volume with all effects disabled", android.widget.Toast.LENGTH_LONG).show()
                } catch (_: Exception) {}
            }
        }
        layout.addView(audioTestBtn)

        // Quick Bug Report
        val bugReportBtn = Button(requireContext()).apply {
            text = "Quick Bug Report"
            setOnClickListener {
                try {
                    mediaController?.sendCustomCommand(
                        androidx.media3.session.SessionCommand("DUMP_PLAYBACK_STATE", android.os.Bundle.EMPTY),
                        android.os.Bundle.EMPTY
                    )
                    android.widget.Toast.makeText(requireContext(), "Playback state dumped to logcat", android.widget.Toast.LENGTH_SHORT).show()
                } catch (_: Exception) {}
            }
        }
        layout.addView(bugReportBtn)

        // ReplayGain section
        val rgHeader = TextView(requireContext()).apply {
            text = "ReplayGain Normalization"
            textSize = 18f
            setPadding(0, 24, 0, 8)
        }
        layout.addView(rgHeader)

        val rgEnable = CheckBox(requireContext()).apply {
            text = "Enable ReplayGain normalization"
            isChecked = settingsPrefs.getBoolean("replaygain_enabled", false)
            setOnCheckedChangeListener { _, checked ->
                settingsPrefs.edit().putBoolean("replaygain_enabled", checked).apply()
                Toast.makeText(requireContext(), if (checked) "ReplayGain enabled" else "ReplayGain disabled", Toast.LENGTH_SHORT).show()
            }
        }
        layout.addView(rgEnable)

        // Mode selector (Track vs Album)
        val modeLabel = TextView(requireContext()).apply {
            text = "ReplayGain mode"
            setPadding(0, 8, 0, 4)
        }
        layout.addView(modeLabel)
        val modeGroup = RadioGroup(requireContext()).apply { orientation = RadioGroup.HORIZONTAL }
        val trackRb = RadioButton(requireContext()).apply { text = "Track" }
        val albumRb = RadioButton(requireContext()).apply { text = "Album" }
        modeGroup.addView(trackRb)
        modeGroup.addView(albumRb)
        val savedMode = settingsPrefs.getString("replaygain_mode", "track") ?: "track"
        if (savedMode == "album") albumRb.isChecked = true else trackRb.isChecked = true
        modeGroup.setOnCheckedChangeListener { _, checkedId ->
            val mode = if (checkedId == albumRb.id) "album" else "track"
            settingsPrefs.edit().putString("replaygain_mode", mode).apply()
        }
        layout.addView(modeGroup)

        // Preamp slider (-12 to +12 dB)
        val preampLabel = TextView(requireContext()).apply { text = "Preamp (dB)" }
        layout.addView(preampLabel)
        val preampValue = TextView(requireContext())
        layout.addView(preampValue)
        val preampSeek = SeekBar(requireContext()).apply {
            max = 240 // -12..+12 mapped to 0..240
            progress = ((settingsPrefs.getFloat("replaygain_preamp_db", 0f) + 12f) * 10f).toInt().coerceIn(0, 240)
        }
        preampValue.text = String.format("%.1f dB", preampSeek.progress / 10f - 12f)
        preampSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, p: Int, fromUser: Boolean) {
                val db = p / 10f - 12f
                preampValue.text = String.format("%.1f dB", db)
                if (fromUser) settingsPrefs.edit().putFloat("replaygain_preamp_db", db).apply()
            }
            override fun onStartTrackingTouch(sb: SeekBar?) {}
            override fun onStopTrackingTouch(sb: SeekBar?) {}
        })
        layout.addView(preampSeek)

        // Fallback gain when no tags (-12..+12 dB)
        val fallbackLabel = TextView(requireContext()).apply { text = "Fallback gain (dB) for files without tags" }
        layout.addView(fallbackLabel)
        val fallbackValue = TextView(requireContext())
        layout.addView(fallbackValue)
        val fallbackSeek = SeekBar(requireContext()).apply {
            max = 240
            progress = ((settingsPrefs.getFloat("replaygain_fallback_db", 0f) + 12f) * 10f).toInt().coerceIn(0, 240)
        }
        fallbackValue.text = String.format("%.1f dB", fallbackSeek.progress / 10f - 12f)
        fallbackSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, p: Int, fromUser: Boolean) {
                val db = p / 10f - 12f
                fallbackValue.text = String.format("%.1f dB", db)
                if (fromUser) settingsPrefs.edit().putFloat("replaygain_fallback_db", db).apply()
            }
            override fun onStartTrackingTouch(sb: SeekBar?) {}
            override fun onStopTrackingTouch(sb: SeekBar?) {}
        })
        layout.addView(fallbackSeek)

        val preventClipToggle = CheckBox(requireContext()).apply {
            text = "Prevent clipping"
            isChecked = settingsPrefs.getBoolean("replaygain_prevent_clipping", true)
            setOnCheckedChangeListener { _, checked ->
                settingsPrefs.edit().putBoolean("replaygain_prevent_clipping", checked).apply()
            }
        }
        layout.addView(preventClipToggle)

        val allowBoostToggle = CheckBox(requireContext()).apply {
            text = "Allow positive gain (uses Loudness Enhancer if supported)"
            isChecked = settingsPrefs.getBoolean("replaygain_allow_boost", false)
            setOnCheckedChangeListener { _, checked ->
                settingsPrefs.edit().putBoolean("replaygain_allow_boost", checked).apply()
            }
        }
        layout.addView(allowBoostToggle)

        val pitchPrefs = requireContext().getSharedPreferences("settings", 0)
        val savedSemitones = pitchPrefs.getInt("pitch_semitones", 0)

        val valueLabel = TextView(requireContext()).apply {
            textSize = 16f
        }

        fun semitonesToPitch(semi: Int): Float {
            return Math.pow(2.0, semi / 12.0).toFloat()
        }

        fun updateLabel(semi: Int) {
            val pitch = semitonesToPitch(semi)
            valueLabel.text = "Current: ${semi} st  (×${"" + String.format("%.3f", pitch)})"
        }

        updateLabel(savedSemitones)
        layout.addView(valueLabel)

        val seek = SeekBar(requireContext()).apply {
            max = 24 // -12..+12
            progress = savedSemitones + 12
        }
        layout.addView(seek)

        val reset = Button(requireContext()).apply {
            text = "Reset to 0 st"
        }
        layout.addView(reset)

        fun applyPitch(semi: Int) {
            val pitch = semitonesToPitch(semi)
            // Persist
            pitchPrefs.edit().putInt("pitch_semitones", semi).putFloat("pitch_factor", pitch).apply()
            // Apply to running session if available
            mediaController?.let { controller ->
                try {
                    // Update controller params locally
                    val current = controller.playbackParameters
                    controller.playbackParameters = androidx.media3.common.PlaybackParameters(current.speed, pitch)
                } catch (_: Exception) {}
            }
        }

        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                val semi = progress - 12
                updateLabel(semi)
                if (fromUser) applyPitch(semi)
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        reset.setOnClickListener {
            seek.progress = 12
            applyPitch(0)
            updateLabel(0)
        }

        // --- Playback Speed ---
        val speedHeader = TextView(requireContext()).apply {
            text = "Playback Speed"
            textSize = 18f
            setPadding(0, 24, 0, 8)
        }
        layout.addView(speedHeader)

        val speedLabel = TextView(requireContext()).apply { text = "1.00x" }
        layout.addView(speedLabel)

        val savedSpeed = pitchPrefs.getFloat("playback_speed", 1.0f)
        fun speedToProgress(sp: Float) = ((sp - 0.25f) * 100).toInt().coerceIn(0, 175) // 0.25..2.0
        fun progressToSpeed(p: Int) = 0.25f + (p.toFloat() / 100f)

        val speedSeek = SeekBar(requireContext()).apply {
            max = 175
            progress = speedToProgress(savedSpeed)
        }
        layout.addView(speedSeek)

        fun applySpeed(sp: Float) {
            // Persist
            pitchPrefs.edit().putFloat("playback_speed", sp).apply()
            speedLabel.text = String.format("%.2fx", sp)
            // Apply live
            mediaController?.let { controller ->
                try {
                    val cur = controller.playbackParameters
                    controller.playbackParameters = androidx.media3.common.PlaybackParameters(sp, cur.pitch)
                } catch (_: Exception) {}
            }
        }

        speedSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                val sp = progressToSpeed(progress)
                speedLabel.text = String.format("%.2fx", sp)
                if (fromUser) applySpeed(sp)
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // Info note
        val note = TextView(requireContext()).apply {
            text = "Note: Pitch is independent of speed. Some devices may exhibit artifacts at extreme values."
            textSize = 12f
        }
        layout.addView(note)

        // --- Reverb ---
        val reverbHeader = TextView(requireContext()).apply {
            text = "Reverb"
            textSize = 18f
            setPadding(0, 24, 0, 8)
        }
        layout.addView(reverbHeader)

        val reverbLabel = TextView(requireContext()).apply { text = "Reverb 0%" }
        layout.addView(reverbLabel)

        val savedPreset = pitchPrefs.getInt("reverb_preset", 0)
        val reverbSeek = SeekBar(requireContext()).apply {
            max = 1000
            progress = when (savedPreset) {
                0 -> 0
                1 -> 150
                2 -> 300
                3 -> 500
                4 -> 750
                5 -> 900
                else -> 980
            }
        }
        layout.addView(reverbSeek)

        fun applyReverbPresetFromProgress(p: Int) {
            reverbLabel.text = "Reverb ${'$'}{p / 10}%"
            val preset: Short = when {
                p < 50 -> 0
                p < 200 -> 1
                p < 400 -> 2
                p < 600 -> 3
                p < 800 -> 4
                p < 950 -> 5
                else -> 6
            }.toShort()
            pitchPrefs.edit().putInt("reverb_preset", preset.toInt()).apply()
            mediaController?.let { controller ->
                try {
                    controller.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_REVERB", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("preset" to preset.toInt())
                    )
                } catch (_: Exception) {}
            }
        }

        reverbSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) applyReverbPresetFromProgress(progress)
                else reverbLabel.text = "Reverb ${'$'}{progress / 10}%"
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // --- App Volume ---
        val volHeader = TextView(requireContext()).apply {
            text = "App Volume"
            textSize = 18f
            setPadding(0, 24, 0, 8)
        }
        layout.addView(volHeader)

        val savedVol = pitchPrefs.getFloat("app_volume", 1.0f).coerceIn(0f, 1f)
        val volLabel = TextView(requireContext()).apply {
            setPadding(12, 6, 12, 6)
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_primary))
            background = ContextCompat.getDrawable(requireContext(), com.stash.opusplayer.R.drawable.duration_background)
            textSize = 12f
        }
        fun updateVolLabel(v: Float) {
            val gamma = 2.0
            val amp = Math.pow(v.toDouble(), gamma).toFloat()
            volLabel.text = "Volume: ${'$'}{(v * 100).toInt()}% (effective ${'$'}{(amp * 100).toInt()}%)"
        }

        // Volume row with badge + Reset
        val volRow = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
        }
        volRow.addView(volLabel)
        val volSpacer = Space(requireContext()).apply { layoutParams = LinearLayout.LayoutParams(0, 1, 1f) }
        volRow.addView(volSpacer)
        val volReset = Button(requireContext()).apply {
            text = "Reset"
            textSize = 12f
            setOnClickListener {
                val def = 1.0f
                pitchPrefs.edit().putFloat("app_volume", def).apply()
                volSeekRef?.progress = 100
                updateVolLabel(def)
                mediaController?.let { controller ->
                    try {
                        controller.sendCustomCommand(
                            androidx.media3.session.SessionCommand("SET_APP_VOLUME", android.os.Bundle.EMPTY),
                            androidx.core.os.bundleOf("volume" to def)
                        )
                    } catch (_: Exception) {}
                }
            }
        }
        volRow.addView(volReset)
        layout.addView(volRow)
        volLabelRef = volLabel

        updateVolLabel(savedVol)

        val volSeek = SeekBar(requireContext()).apply {
            max = 100
            progress = (savedVol * 100f).toInt()
        }
        layout.addView(volSeek)
        volSeekRef = volSeek

        fun applyAppVolume(progress: Int) {
            val v = (progress / 100f).coerceIn(0f, 1f)
            pitchPrefs.edit().putFloat("app_volume", v).apply()
            updateVolLabel(v)
            mediaController?.let { controller ->
                try {
                    controller.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_APP_VOLUME", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("volume" to v)
                    )
                } catch (_: Exception) {}
            }
        }
        volSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) applyAppVolume(progress) else updateVolLabel(progress / 100f)
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // --- Audio Focus ---
        val afToggle = CheckBox(requireContext()).apply {
            text = "Enable audio focus (pause/duck on interruptions)"
            isChecked = pitchPrefs.getBoolean("audio_focus_enabled", true)
            setOnCheckedChangeListener { _, isChecked ->
                pitchPrefs.edit().putBoolean("audio_focus_enabled", isChecked).apply()
                mediaController?.let { controller ->
                    try {
                        controller.sendCustomCommand(
                            androidx.media3.session.SessionCommand("SET_AUDIO_FOCUS", android.os.Bundle.EMPTY),
                            androidx.core.os.bundleOf("enabled" to isChecked)
                        )
                    } catch (_: Exception) {}
                }
            }
        }
        layout.addView(afToggle)

        // --- Crossfade ---
        val cfToggle = CheckBox(requireContext()).apply {
            text = "Enable crossfade between tracks"
            isChecked = pitchPrefs.getBoolean("crossfade_enabled", false)
        }
        layout.addView(cfToggle)
        cfToggleRef = cfToggle

        val cfLabel = TextView(requireContext())
        val savedCf = pitchPrefs.getLong("crossfade_duration_ms", 1000L).coerceIn(0L, 5000L)
        fun updateCfLabel(ms: Long) { cfLabel.text = "Crossfade duration: ${'$'}{ms} ms" }
        updateCfLabel(savedCf)
        // Crossfade row with badge + Reset
        val cfRow = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
        }
        cfRow.addView(cfLabel)
        cfLabelRef = cfLabel
        val cfSpacer = Space(requireContext()).apply { layoutParams = LinearLayout.LayoutParams(0, 1, 1f) }
        cfRow.addView(cfSpacer)
        val cfReset = Button(requireContext()).apply {
            text = "Reset"
            textSize = 12f
            setOnClickListener {
                val defMs = 1000L
                pitchPrefs.edit().putLong("crossfade_duration_ms", defMs).apply()
                cfSeekRef?.progress = defMs.toInt()
                updateCfLabel(defMs)
                mediaController?.let { controller ->
                    try {
                        controller.sendCustomCommand(
                            androidx.media3.session.SessionCommand("SET_CROSSFADE_DURATION", android.os.Bundle.EMPTY),
                            androidx.core.os.bundleOf("duration_ms" to defMs)
                        )
                    } catch (_: Exception) {}
                }
            }
        }
        cfRow.addView(cfReset)
        layout.addView(cfRow)

        val cfSeek = SeekBar(requireContext()).apply {
            max = 5000
            progress = savedCf.toInt()
            isEnabled = cfToggle.isChecked
        }
        layout.addView(cfSeek)
        cfSeekRef = cfSeek

        val trueCfToggle = CheckBox(requireContext()).apply {
            text = "Experimental: True crossfade (dual player)"
            val prefs = requireContext().getSharedPreferences("settings", 0)
            isChecked = prefs.getBoolean("experimental_true_crossfade", true)
            setOnCheckedChangeListener { _, enabled ->
                prefs.edit().putBoolean("experimental_true_crossfade", enabled).apply()
                Toast.makeText(requireContext(), if (enabled) "True crossfade enabled" else "True crossfade disabled", Toast.LENGTH_SHORT).show()
            }
        }
        layout.addView(trueCfToggle)

        // Crossfade polling toggle (disable to avoid background races)
        val cfPollingToggle = CheckBox(requireContext()).apply {
            text = "Enable crossfade polling (disable if you see track switch issues)"
            val prefs = requireContext().getSharedPreferences("settings", 0)
            isChecked = prefs.getBoolean("crossfade_polling_enabled", true)
            setOnCheckedChangeListener { _, enabled ->
                prefs.edit().putBoolean("crossfade_polling_enabled", enabled).apply()
                // Inform service immediately
                try {
                    mediaController?.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_CROSSFADE_POLLING_ENABLED", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("enabled" to enabled)
                    )
                } catch (_: Exception) {}
            }
        }
        layout.addView(cfPollingToggle)

        cfToggle.setOnCheckedChangeListener { _, enabled ->
            pitchPrefs.edit().putBoolean("crossfade_enabled", enabled).apply()
            cfSeek.isEnabled = enabled
            mediaController?.let { controller ->
                try {
                    controller.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_CROSSFADE_ENABLED", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("enabled" to enabled)
                    )
                } catch (_: Exception) {}
            }
        }
        cfSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) { updateCfLabel(progress.toLong()); return }
                val ms = progress.coerceIn(0, 5000).toLong()
                updateCfLabel(ms)
                pitchPrefs.edit().putLong("crossfade_duration_ms", ms).apply()
                mediaController?.let { controller ->
                    try {
                        controller.sendCustomCommand(
                            androidx.media3.session.SessionCommand("SET_CROSSFADE_DURATION", android.os.Bundle.EMPTY),
                            androidx.core.os.bundleOf("duration_ms" to ms)
                        )
                    } catch (_: Exception) {}
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // Listen to external changes to keep labels accurate
        try {
            val sp = requireContext().getSharedPreferences("settings", 0)
            settingsListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { prefsChanged, key ->
                when (key) {
                    "app_volume" -> {
                        val v = prefsChanged.getFloat("app_volume", savedVol).coerceIn(0f, 1f)
                        volSeekRef?.progress = (v * 100f).toInt()
                        updateVolLabel(v)
                    }
                    "crossfade_enabled" -> {
                        val en = prefsChanged.getBoolean("crossfade_enabled", cfToggleRef?.isChecked ?: false)
                        cfToggleRef?.isChecked = en
                        cfSeekRef?.isEnabled = en
                    }
                    "crossfade_duration_ms" -> {
                        val ms = prefsChanged.getLong("crossfade_duration_ms", savedCf).coerceIn(0L, 5000L)
                        cfSeekRef?.progress = ms.toInt()
                        updateCfLabel(ms)
                    }
                }
            }
            sp.registerOnSharedPreferenceChangeListener(settingsListener)
        } catch (_: Exception) {}

        scrollView.addView(layout)
        
        // Apply comprehensive responsive design to the entire layout
        ResponsiveUtils.applyResponsiveDesign(layout)
        
        return scrollView
    }
    
    private fun addSectionHeader(parent: LinearLayout, title: String) {
        val header = TextView(requireContext()).apply {
            text = title
            ResponsiveUtils.applyResponsiveTextSize(this, 16f) // Responsive section header size
            ResponsiveUtils.applyResponsivePadding(this, 0, 16, 0, 8) // Responsive padding
            setTextColor(ContextCompat.getColor(requireContext(), android.R.color.holo_blue_bright))
        }
        parent.addView(header)
    }
    private fun pickMusicFolder() {
        try {
            folderPickerLauncher.launch(null)
        } catch (_: Exception) {
            Toast.makeText(requireContext(), "Unable to open folder picker", Toast.LENGTH_SHORT).show()
        }
    }
    private fun showManageFoldersDialog() {
        val repo = com.stash.opusplayer.data.MusicRepository(requireContext())
        val trees = repo.getCustomMusicFolderTreeUris().toList()
        if (trees.isEmpty()) {
            Toast.makeText(requireContext(), "No folders added", Toast.LENGTH_SHORT).show()
            return
        }
        val names = trees.map { uri ->
            try { android.net.Uri.parse(uri).lastPathSegment ?: uri } catch (_: Exception) { uri }
        }.toTypedArray()

        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle("Manage Folders")
            .setItems(names) { _, which ->
                val chosen = trees[which]
                // Remove chosen URI
                val prefs = androidx.preference.PreferenceManager.getDefaultSharedPreferences(requireContext())
                val set = prefs.getStringSet("custom_music_folders_tree", setOf())?.toMutableSet() ?: mutableSetOf()
                set.remove(chosen)
                prefs.edit().putStringSet("custom_music_folders_tree", set).apply()
                Toast.makeText(requireContext(), "Folder removed", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("Close", null)
            .show()
    }
    
    private fun showAWSCredentialsDialog() {
        val awsConfig = com.stash.opusplayer.cloud.AWSConfig.getInstance(requireContext())
        
        // Create dialog layout
        val dialogLayout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        
        val titleText = TextView(requireContext()).apply {
            text = "AWS Credentials Configuration"
            textSize = 18f
            setPadding(0, 0, 0, 16)
        }
        dialogLayout.addView(titleText)
        
        val infoText = TextView(requireContext()).apply {
            text = "Enter your AWS Access Key ID and Secret Access Key. These will be stored securely on your device."
            textSize = 12f
            setPadding(0, 0, 0, 16)
        }
        dialogLayout.addView(infoText)
        
        val accessKeyLabel = TextView(requireContext()).apply {
            text = "Access Key ID:"
            setPadding(0, 8, 0, 4)
        }
        dialogLayout.addView(accessKeyLabel)
        
        val accessKeyInput = EditText(requireContext()).apply {
            hint = "AKIA..."
            inputType = android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        }
        dialogLayout.addView(accessKeyInput)
        
        val secretKeyLabel = TextView(requireContext()).apply {
            text = "Secret Access Key:"
            setPadding(0, 16, 0, 4)
        }
        dialogLayout.addView(secretKeyLabel)
        
        val secretKeyInput = EditText(requireContext()).apply {
            hint = "Your secret key..."
            inputType = android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        dialogLayout.addView(secretKeyInput)
        
        val statusText = TextView(requireContext()).apply {
            text = "Current source: ${awsConfig.getCredentialSource()}"
            textSize = 11f
            setPadding(0, 16, 0, 0)
        }
        dialogLayout.addView(statusText)
        
        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setView(dialogLayout)
            .setTitle("AWS Credentials")
            .setPositiveButton("Save") { _, _ ->
                val accessKey = accessKeyInput.text.toString().trim()
                val secretKey = secretKeyInput.text.toString().trim()
                
                if (accessKey.isEmpty() || secretKey.isEmpty()) {
                    Toast.makeText(requireContext(), "Both fields are required", Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                
                if (awsConfig.storeCredentials(accessKey, secretKey)) {
                    Toast.makeText(requireContext(), "Credentials saved successfully", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(requireContext(), "Failed to save credentials", Toast.LENGTH_SHORT).show()
                }
            }
            .setNeutralButton("Clear") { _, _ ->
                if (awsConfig.clearStoredCredentials()) {
                    Toast.makeText(requireContext(), "Credentials cleared", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
    
    private fun testAWSConnection() {
        val awsConfig = com.stash.opusplayer.cloud.AWSConfig.getInstance(requireContext())
        
        lifecycleScope.launch {
            try {
                // Show progress
                Toast.makeText(requireContext(), "Testing AWS connection...", Toast.LENGTH_SHORT).show()
                
                // Initialize AWS if needed
                val initSuccess = awsConfig.initialize()
                if (!initSuccess) {
                    Toast.makeText(requireContext(), "Failed to initialize AWS. Check credentials.", Toast.LENGTH_LONG).show()
                    return@launch
                }
                
                // Test connection
                val testSuccess = awsConfig.testConnection()
                if (testSuccess) {
                    Toast.makeText(requireContext(), "✅ Connection successful!", Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(requireContext(), "❌ Connection failed. Check credentials and permissions.", Toast.LENGTH_LONG).show()
                }
                
            } catch (e: Exception) {
                Toast.makeText(requireContext(), "Connection error: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }
    
    private fun performManualSync() {
        val cloudSyncService = com.stash.opusplayer.cloud.services.CloudSyncService.getInstance(requireContext())
        
        lifecycleScope.launch {
            try {
                Toast.makeText(requireContext(), "Starting manual sync...", Toast.LENGTH_SHORT).show()
                
                val result = cloudSyncService.syncAll()
                if (result.success) {
                    Toast.makeText(requireContext(), "✅ Sync completed successfully!", Toast.LENGTH_LONG).show()
                } else {
                    Toast.makeText(requireContext(), "❌ Sync failed. Check connection.", Toast.LENGTH_LONG).show()
                }
                
            } catch (e: Exception) {
                Toast.makeText(requireContext(), "Sync error: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun buildAppearanceContent(): View {
        val scrollView = ScrollView(requireContext())
        val layout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            // Apply responsive padding instead of fixed padding
            ResponsiveUtils.applyResponsivePadding(this, 16, 16, 16, 16)
        }

        val currentPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
        
        // Title with responsive text size
        val title = TextView(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.settings_appearance_title)
            ResponsiveUtils.applyResponsiveTextSize(this, 20f) // Responsive title size
            ResponsiveUtils.applyResponsivePadding(this, 0, 0, 0, 16)
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_primary))
        }
        layout.addView(title)
        
        // Quick Theme Presets Section
        addSectionHeader(layout, "Quick Themes")
        val presetChips = com.google.android.material.chip.ChipGroup(requireContext()).apply {
            isSingleSelection = false
        }
        
        com.stash.opusplayer.ui.appearance.AppearancePresets.listPresets().forEach { preset ->
            val chip = com.google.android.material.chip.Chip(requireContext()).apply {
                text = preset.name
                isCheckable = true
                setOnClickListener {
                    applyAppearancePreset(preset)
                    isChecked = false
                }
            }
            presetChips.addView(chip)
        }
        layout.addView(presetChips)
        
        // Colors Section
        addSectionHeader(layout, getString(com.stash.opusplayer.R.string.settings_appearance_theme_colors))
        
        // Color buttons for main colors
        val colorButtons = listOf(
            "Primary Color" to currentPrefs.primaryColor,
            "Accent Color" to currentPrefs.accentColor,
            "Background Color" to currentPrefs.backgroundColor,
            "Primary Text Color" to currentPrefs.textPrimaryColor,
            "Secondary Text Color" to currentPrefs.textSecondaryColor
        )
        
        colorButtons.forEach { (label, color) ->
            val colorRow = LinearLayout(requireContext()).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, 8, 0, 8)
            }
            
            val labelView = TextView(requireContext()).apply {
                text = label
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_primary))
            }
            colorRow.addView(labelView)
            
            val colorSwatch = View(requireContext()).apply {
                val size = (48 * resources.displayMetrics.density).toInt()
                layoutParams = LinearLayout.LayoutParams(size, size)
                setBackgroundColor(color)
                setOnClickListener {
                    // Determine which color we're changing
                    val colorKey = when (label) {
                        "Primary Color" -> "primary"
                        "Accent Color" -> "accent"
                        "Background Color" -> "background"
                        "Primary Text Color" -> "text_primary"
                        "Secondary Text Color" -> "text_secondary"
                        else -> return@setOnClickListener
                    }
                    
                    showColorPicker(label, color) { newColor ->
                        // Update the swatch immediately
                        setBackgroundColor(newColor)
                        
                        // Save the new color to preferences
                        val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                        val updatedPrefs = when (colorKey) {
                            "primary" -> latestPrefs.copy(primaryColor = newColor)
                            "accent" -> latestPrefs.copy(accentColor = newColor)
                            "background" -> latestPrefs.copy(backgroundColor = newColor)
                            "text_primary" -> latestPrefs.copy(textPrimaryColor = newColor)
                            "text_secondary" -> latestPrefs.copy(textSecondaryColor = newColor)
                            else -> latestPrefs
                        }
                        updatedPrefs.saveToPrefs(requireContext())
                        
                        // Persist as recent color
                        com.stash.opusplayer.ui.appearance.AppearancePreferences.persistRecentColor(requireContext(), newColor)
                        
                        // Apply the changes
                        com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
                        
                        Toast.makeText(requireContext(), "$label updated!", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            colorRow.addView(colorSwatch)
            layout.addView(colorRow)
        }
        
        // Typography Section
        addSectionHeader(layout, getString(com.stash.opusplayer.R.string.settings_appearance_typography))
        
        // Font Scale
        val fontScaleLabel = TextView(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.appearance_font_scale)
            setPadding(0, 8, 0, 8)
        }
        layout.addView(fontScaleLabel)
        
        val fontScaleSpinner = Spinner(requireContext())
        val fontScales = listOf(
            "Small (85%)" to 0.85f,
            "Medium (100%)" to 1.0f, 
            "Large (115%)" to 1.15f,
            "Extra Large (130%)" to 1.3f
        )
        val fontAdapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, fontScales.map { it.first })
        fontAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        fontScaleSpinner.adapter = fontAdapter
        fontScaleSpinner.setSelection(fontScales.indexOfFirst { it.second == currentPrefs.fontScale }.coerceAtLeast(0))
        fontScaleSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val newScale = fontScales[position].second
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(fontScale = newScale)
                updatedPrefs.saveToPrefs(requireContext())
                // Don't recreate activity to prevent tab switching - just broadcast dynamic change
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
                Toast.makeText(requireContext(), "Font scale changed. Changes will apply when app is restarted.", Toast.LENGTH_SHORT).show()
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        layout.addView(fontScaleSpinner)
        
        // Bold Titles Toggle
        val boldToggle = CheckBox(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.appearance_title_weight_bold)
            isChecked = currentPrefs.titleBold
            setOnCheckedChangeListener { _, isChecked ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(titleBold = isChecked)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        layout.addView(boldToggle)
        
        // UI Elements Section
        addSectionHeader(layout, getString(com.stash.opusplayer.R.string.settings_appearance_ui_elements))
        
        // Shadows Toggle
        val shadowsToggle = CheckBox(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.appearance_shadows_enable)
            isChecked = currentPrefs.shadowsEnabled
            setOnCheckedChangeListener { _, isChecked ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(shadowsEnabled = isChecked)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        layout.addView(shadowsToggle)
        
        // Enhanced Animation Settings Section
        addSectionHeader(layout, "Enhanced Animation Settings")
        
        // Main Animations Toggle
        val animationsToggle = CheckBox(requireContext()).apply {
            text = "Enable UI Animations"
            isChecked = currentPrefs.animationsEnabled
            setOnCheckedChangeListener { _, isChecked ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(animationsEnabled = isChecked)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        layout.addView(animationsToggle)
        
        // Advanced Animation Settings Button
        val advancedAnimationButton = com.google.android.material.button.MaterialButton(requireContext()).apply {
            text = "⚡ Advanced Animation Settings"
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.accent_color))
            setOnClickListener {
                // Launch the AnimationSettingsFragment
                try {
                    val fragment = com.stash.opusplayer.ui.preferences.AnimationSettingsFragment()
                    parentFragmentManager.beginTransaction()
                        .replace(com.stash.opusplayer.R.id.main_content, fragment)
                        .addToBackStack("animation_settings")
                        .commit()
                } catch (e: Exception) {
                    Toast.makeText(requireContext(), "Opening animation settings...", Toast.LENGTH_SHORT).show()
                }
            }
        }
        layout.addView(advancedAnimationButton)
        
        // Animation Speed
        val animSpeedLabel = TextView(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.appearance_animation_speed)
            setPadding(0, 16, 0, 8)
        }
        layout.addView(animSpeedLabel)
        
        // Visual Customization Section
        addSectionHeader(layout, "🎨 Visual Customization")
        
        // Visual Customization Button
        val visualCustomizationButton = com.google.android.material.button.MaterialButton(requireContext()).apply {
            text = "🖼️ Photo Backgrounds & Effects"
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.secondary_color))
            setOnClickListener {
                // Launch the VisualCustomizationFragment
                try {
                    val fragment = com.stash.opusplayer.ui.customization.VisualCustomizationFragment()
                    parentFragmentManager.beginTransaction()
                        .replace(com.stash.opusplayer.R.id.main_content, fragment)
                        .addToBackStack("visual_customization")
                        .commit()
                } catch (e: Exception) {
                    Toast.makeText(requireContext(), "Opening visual customization...", Toast.LENGTH_SHORT).show()
                }
            }
        }
        layout.addView(visualCustomizationButton)
        
        // Enhanced SynthWave Visualizer Section
        addSectionHeader(layout, "🌊 Enhanced Visualizer")
        
        // Quick SynthWave Settings
        val synthwavePrefs = androidx.preference.PreferenceManager.getDefaultSharedPreferences(requireContext())
        
        val synthwaveLightningToggle = CheckBox(requireContext()).apply {
            text = "⚡ Lightning Effects"
            isChecked = synthwavePrefs.getBoolean("synthwave_lightning_enabled", true)
            setOnCheckedChangeListener { _, isChecked ->
                synthwavePrefs.edit().putBoolean("synthwave_lightning_enabled", isChecked).apply()
            }
        }
        layout.addView(synthwaveLightningToggle)
        
        val synthwaveParticlesToggle = CheckBox(requireContext()).apply {
            text = "✨ Particle Trails"
            isChecked = synthwavePrefs.getBoolean("synthwave_particles_enabled", true)
            setOnCheckedChangeListener { _, isChecked ->
                synthwavePrefs.edit().putBoolean("synthwave_particles_enabled", isChecked).apply()
            }
        }
        layout.addView(synthwaveParticlesToggle)
        
        val synthwaveRipplesToggle = CheckBox(requireContext()).apply {
            text = "🌊 Ripple Effects"
            isChecked = synthwavePrefs.getBoolean("synthwave_ripples_enabled", true)
            setOnCheckedChangeListener { _, isChecked ->
                synthwavePrefs.edit().putBoolean("synthwave_ripples_enabled", isChecked).apply()
            }
        }
        layout.addView(synthwaveRipplesToggle)
        
        val animSpeedSpinner = Spinner(requireContext())
        val animSpeeds = listOf(
            "Slow" to com.stash.opusplayer.ui.appearance.AppearancePreferences.AnimationSpeed.SLOW,
            "Normal" to com.stash.opusplayer.ui.appearance.AppearancePreferences.AnimationSpeed.NORMAL,
            "Fast" to com.stash.opusplayer.ui.appearance.AppearancePreferences.AnimationSpeed.FAST
        )
        val animSpeedAdapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, animSpeeds.map { it.first })
        animSpeedAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        animSpeedSpinner.adapter = animSpeedAdapter
        animSpeedSpinner.setSelection(animSpeeds.indexOfFirst { it.second == currentPrefs.animationSpeed }.coerceAtLeast(0))
        animSpeedSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val newSpeed = animSpeeds[position].second
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(animationSpeed = newSpeed)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        layout.addView(animSpeedSpinner)
        
        // Mini Player Section
        addSectionHeader(layout, "🎵 Mini Player Settings")
        
        // Mini Player Style Selection
        val miniPlayerToggleManager = com.stash.opusplayer.ui.managers.MiniPlayerToggleManager(requireContext())
        
        val styleLabel = TextView(requireContext()).apply {
            text = "Mini Player Style"
            textSize = 16f
            setPadding(0, 8, 0, 8)
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_primary))
        }
        layout.addView(styleLabel)
        
        val styleSpinner = Spinner(requireContext())
        val availableStyles = miniPlayerToggleManager.getAvailableStyles()
        val styleAdapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, availableStyles.map { it.second })
        styleAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        styleSpinner.adapter = styleAdapter
        
        val currentStyle = miniPlayerToggleManager.getMiniPlayerStyle()
        val currentIndex = availableStyles.indexOfFirst { it.first == currentStyle }.coerceAtLeast(0)
        styleSpinner.setSelection(currentIndex)
        
        styleSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val selectedStyle = availableStyles[position].first
                miniPlayerToggleManager.setMiniPlayerStyle(selectedStyle)
                updateStyleFeaturesDisplay(layout, miniPlayerToggleManager, selectedStyle)
                Toast.makeText(requireContext(), "Mini Player style changed to: ${availableStyles[position].second}", Toast.LENGTH_SHORT).show()
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        layout.addView(styleSpinner)
        
        // Features display
        val featuresContainer = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            id = View.generateViewId()
        }
        layout.addView(featuresContainer)
        updateStyleFeaturesDisplay(featuresContainer, miniPlayerToggleManager, currentStyle)
        
        // Show Album Art Toggle
        val showArtToggle = CheckBox(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.appearance_mini_player_show_art)
            isChecked = currentPrefs.miniPlayerShowArt
            setOnCheckedChangeListener { _, isChecked ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(miniPlayerShowArt = isChecked)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        layout.addView(showArtToggle)
        
        // Show Artist Toggle
        val showArtistToggle = CheckBox(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.appearance_mini_player_show_artist)
            isChecked = currentPrefs.miniPlayerShowArtist
            setOnCheckedChangeListener { _, isChecked ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(miniPlayerShowArtist = isChecked)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        layout.addView(showArtistToggle)
        
        // Compact Mode Toggle
        val compactModeToggle = CheckBox(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.appearance_mini_player_compact_mode)
            isChecked = currentPrefs.miniPlayerCompactMode
            setOnCheckedChangeListener { _, isChecked ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(miniPlayerCompactMode = isChecked)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        layout.addView(compactModeToggle)
        
        // SynthWave Visualizer Section
        addSectionHeader(layout, "SynthWave Visualizer")
        
        // Progress Mode Toggle
        val synthWaveProgressToggle = CheckBox(requireContext()).apply {
            text = "Progress-based Waveform"
            isChecked = currentPrefs.synthWaveProgressMode
            setOnCheckedChangeListener { _, isChecked ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(synthWaveProgressMode = isChecked)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        layout.addView(synthWaveProgressToggle)
        
        // Use Custom Colors Toggle
        val synthWaveCustomToggle = CheckBox(requireContext()).apply {
            text = "Use Custom Colors"
            isChecked = currentPrefs.synthWaveUseCustomColors
            setOnCheckedChangeListener { _, isChecked ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(synthWaveUseCustomColors = isChecked)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        layout.addView(synthWaveCustomToggle)
        
        // SynthWave Primary Color
        val synthWavePrimaryColorRow = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 8, 0, 8)
        }
        
        val synthWavePrimaryColorLabel = TextView(requireContext()).apply {
            text = "SynthWave Primary Color"
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_primary))
        }
        synthWavePrimaryColorRow.addView(synthWavePrimaryColorLabel)
        
        val synthWavePrimaryColorSwatch = View(requireContext()).apply {
            val size = (48 * resources.displayMetrics.density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size)
            setBackgroundColor(currentPrefs.synthWavePrimaryColor)
            setOnClickListener {
                showColorPicker("SynthWave Primary Color", currentPrefs.synthWavePrimaryColor) { newColor ->
                    // Update the swatch immediately
                    setBackgroundColor(newColor)
                    
                    // Save the new color to preferences
                    val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                    val updatedPrefs = latestPrefs.copy(synthWavePrimaryColor = newColor)
                    updatedPrefs.saveToPrefs(requireContext())
                    
                    // Persist as recent color
                    com.stash.opusplayer.ui.appearance.AppearancePreferences.persistRecentColor(requireContext(), newColor)
                    
                    // Apply the changes
                    com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
                    
                    Toast.makeText(requireContext(), "SynthWave Primary Color updated!", Toast.LENGTH_SHORT).show()
                }
            }
        }
        synthWavePrimaryColorRow.addView(synthWavePrimaryColorSwatch)
        layout.addView(synthWavePrimaryColorRow)
        
        // SynthWave Secondary Color
        val synthWaveSecondaryColorRow = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 8, 0, 8)
        }
        
        val synthWaveSecondaryColorLabel = TextView(requireContext()).apply {
            text = "SynthWave Secondary Color"
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_primary))
        }
        synthWaveSecondaryColorRow.addView(synthWaveSecondaryColorLabel)
        
        val synthWaveSecondaryColorSwatch = View(requireContext()).apply {
            val size = (48 * resources.displayMetrics.density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size)
            setBackgroundColor(currentPrefs.synthWaveSecondaryColor)
            setOnClickListener {
                showColorPicker("SynthWave Secondary Color", currentPrefs.synthWaveSecondaryColor) { newColor ->
                    // Update the swatch immediately
                    setBackgroundColor(newColor)
                    
                    // Save the new color to preferences
                    val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                    val updatedPrefs = latestPrefs.copy(synthWaveSecondaryColor = newColor)
                    updatedPrefs.saveToPrefs(requireContext())
                    
                    // Persist as recent color
                    com.stash.opusplayer.ui.appearance.AppearancePreferences.persistRecentColor(requireContext(), newColor)
                    
                    // Apply the changes
                    com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
                    
                    Toast.makeText(requireContext(), "SynthWave Secondary Color updated!", Toast.LENGTH_SHORT).show()
                }
            }
        }
        synthWaveSecondaryColorRow.addView(synthWaveSecondaryColorSwatch)
        layout.addView(synthWaveSecondaryColorRow)
        
        // UI Scale Section
        addSectionHeader(layout, "UI Scaling")
        
        // Button Size Scale
        layout.addView(createSeekBarControl(
            "Button Size",
            (currentPrefs.buttonSizeScale * 100).toInt(),
            80, 120,
            { /* preview update */ },
            { progress ->
                val scale = progress / 100f
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(buttonSizeScale = scale)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        ))
        
        // Card Corner Radius
        layout.addView(createSeekBarControl(
            "Corner Radius",
            currentPrefs.cardCornerRadiusDp,
            8, 32,
            { /* preview update */ },
            { progress ->
                val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
                val updatedPrefs = latestPrefs.copy(cardCornerRadiusDp = progress)
                updatedPrefs.saveToPrefs(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
            }
        ))
        
        // Reset to Defaults Button
        val resetButton = com.google.android.material.button.MaterialButton(requireContext()).apply {
            text = getString(com.stash.opusplayer.R.string.appearance_reset_defaults)
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.error_color))
            setOnClickListener {
                showResetAppearanceDialog()
            }
        }
        layout.addView(resetButton)
        
        scrollView.addView(layout)
        
        // Apply comprehensive responsive design to the entire layout
        ResponsiveUtils.applyResponsiveDesign(layout)
        
        return scrollView
    }
    
    private fun applyAppearancePreset(preset: com.stash.opusplayer.ui.appearance.AppearancePresets.PresetInfo) {
        val latestPrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(requireContext())
        val updatedPrefs = latestPrefs.copy(
            primaryColor = preset.primaryColor,
            accentColor = preset.accentColor,
            backgroundColor = preset.backgroundColor,
            textPrimaryColor = preset.textPrimaryColor,
            textSecondaryColor = preset.textSecondaryColor
        )
        updatedPrefs.saveToPrefs(requireContext())
        com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), false)
        Toast.makeText(requireContext(), "Preset '${preset.name}' applied!", Toast.LENGTH_SHORT).show()
    }
    
    private fun showResetAppearanceDialog() {
        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle(getString(com.stash.opusplayer.R.string.appearance_reset_defaults))
            .setMessage(getString(com.stash.opusplayer.R.string.appearance_confirm_reset_all))
            .setPositiveButton("Reset") { _, _ ->
                com.stash.opusplayer.ui.appearance.AppearancePreferences.resetToDefaults(requireContext())
                com.stash.opusplayer.ui.appearance.ThemeManager.broadcastChange(requireContext(), true)
                activity?.recreate()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
    
    private fun createSeekBarControl(
        title: String,
        initialValue: Int,
        minValue: Int,
        maxValue: Int,
        onPreviewUpdate: (Int) -> Unit,
        onValueChanged: (Int) -> Unit
    ): View {
        val container = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 16, 0, 16)
        }
        
        val labelText = TextView(requireContext()).apply {
            text = "$title: $initialValue"
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_primary))
            setPadding(0, 0, 0, 8)
        }
        container.addView(labelText)
        
        val seekBar = SeekBar(requireContext()).apply {
            max = maxValue - minValue
            progress = initialValue - minValue
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (fromUser) {
                        val value = progress + minValue
                        labelText.text = "$title: $value"
                        onPreviewUpdate(value)
                    }
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    val value = (seekBar?.progress ?: 0) + minValue
                    onValueChanged(value)
                }
            })
        }
        container.addView(seekBar)
        
        return container
    }
    
    private fun showColorPicker(title: String, initialColor: Int, onColorSelected: (Int) -> Unit) {
        val colorPicker = com.stash.opusplayer.ui.appearance.ColorPickerDialog.newInstance(
            initialColor = initialColor,
            onColorSelected = onColorSelected
        )
        colorPicker.show(parentFragmentManager, "color_picker")
    }
    
    private fun clearArtworkCache() {
        // Show confirmation dialog first
        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle("Clear Artwork Cache")
            .setMessage("This will delete all cached album artwork. They will be re-downloaded as needed. Continue?")
            .setPositiveButton("Clear") { _, _ ->
                // Show progress
                val progressToast = Toast.makeText(requireContext(), "🗑️ Clearing cache...", Toast.LENGTH_SHORT)
                progressToast.show()
                
                try {
                    val artworkDir = java.io.File(requireContext().cacheDir, "artwork")
                    val cacheDir = java.io.File(requireContext().cacheDir, "artwork_cache") // Our new cache
                    var deletedFiles = 0
                    
                    if (artworkDir.exists()) {
                        artworkDir.listFiles()?.forEach { 
                            it.delete()
                            deletedFiles++
                        }
                    }
                    
                    if (cacheDir.exists()) {
                        cacheDir.listFiles()?.forEach { 
                            it.delete()
                            deletedFiles++
                        }
                    }
                    
                    // Note: The existing ArtworkCache class doesn't have a clearCache method,
                    // so we manually clean the directory
                    
                    Toast.makeText(
                        requireContext(), 
                        "✅ Artwork cache cleared! ($deletedFiles files removed)", 
                        Toast.LENGTH_LONG
                    ).show()
                } catch (_: Exception) {
                    Toast.makeText(requireContext(), "❌ Failed to clear cache completely", Toast.LENGTH_LONG).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
    
    private fun updateStyleFeaturesDisplay(container: LinearLayout, manager: com.stash.opusplayer.ui.managers.MiniPlayerToggleManager, style: String) {
        container.removeAllViews()
        
        val features = manager.getStyleFeatures(style)
        if (features.isNotEmpty()) {
            val featuresLabel = TextView(requireContext()).apply {
                text = "Features:"
                textSize = 14f
                setPadding(0, 16, 0, 8)
                setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_secondary))
            }
            container.addView(featuresLabel)
            
            features.forEach { feature ->
                val featureView = TextView(requireContext()).apply {
                    text = "• $feature"
                    textSize = 12f
                    setPadding(16, 2, 0, 2)
                    setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_secondary))
                }
                container.addView(featureView)
            }
        }
    }
    
    private fun buildEnhancedFeaturesContent(): View {
        val scrollView = ScrollView(requireContext())
        val layout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            ResponsiveUtils.applyResponsivePadding(this, 16, 16, 16, 16)
        }

        // Title
        val title = TextView(requireContext()).apply {
            text = "🚀 Enhanced Features"
            ResponsiveUtils.applyResponsiveTextSize(this, 20f)
            ResponsiveUtils.applyResponsivePadding(this, 0, 0, 0, 16)
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_primary))
        }
        layout.addView(title)
        
        // Animation Settings Section
        addSectionHeader(layout, "⚡ Advanced Animation Controls")
        
        val animationSettingsButton = com.google.android.material.button.MaterialButton(requireContext()).apply {
            text = "🎬 Animation Settings Panel"
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.accent_color))
            setOnClickListener {
                try {
                    val fragment = com.stash.opusplayer.ui.preferences.AnimationSettingsFragment()
                    parentFragmentManager.beginTransaction()
                        .replace(com.stash.opusplayer.R.id.main_content, fragment)
                        .addToBackStack("animation_settings")
                        .commit()
                } catch (e: Exception) {
                    Toast.makeText(requireContext(), "Opening animation settings...", Toast.LENGTH_SHORT).show()
                }
            }
        }
        layout.addView(animationSettingsButton)
        
        // Visual Customization Section
        addSectionHeader(layout, "🎨 Visual Customization")
        
        val visualCustomizationButton = com.google.android.material.button.MaterialButton(requireContext()).apply {
            text = "🖼️ Photo Backgrounds & Effects"
            setTextColor(Color.WHITE)
            backgroundTintList = ColorStateList.valueOf(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.secondary_color))
            setOnClickListener {
                try {
                    val fragment = com.stash.opusplayer.ui.customization.VisualCustomizationFragment()
                    parentFragmentManager.beginTransaction()
                        .replace(com.stash.opusplayer.R.id.main_content, fragment)
                        .addToBackStack("visual_customization")
                        .commit()
                } catch (e: Exception) {
                    Toast.makeText(requireContext(), "Opening visual customization...", Toast.LENGTH_SHORT).show()
                }
            }
        }
        layout.addView(visualCustomizationButton)
        
        // Enhanced SynthWave Visualizer Section
        addSectionHeader(layout, "🌊 Enhanced SynthWave Visualizer")
        
        val synthwavePrefs = androidx.preference.PreferenceManager.getDefaultSharedPreferences(requireContext())
        
        // Quick toggle controls
        val synthwaveToggles = listOf(
            "⚡ Lightning Effects" to "synthwave_lightning_enabled",
            "✨ Particle Trails" to "synthwave_particles_enabled", 
            "🌊 Ripple Effects" to "synthwave_ripples_enabled",
            "💨 Breathing Animation" to "synthwave_breathing_enabled",
            "🌈 Color Shift Effects" to "synthwave_color_shift_enabled"
        )
        
        synthwaveToggles.forEach { (label, prefKey) ->
            val toggle = CheckBox(requireContext()).apply {
                text = label
                isChecked = synthwavePrefs.getBoolean(prefKey, true)
                setOnCheckedChangeListener { _, isChecked ->
                    synthwavePrefs.edit().putBoolean(prefKey, isChecked).apply()
                }
            }
            layout.addView(toggle)
        }
        
        // Audio Enhancement Section
        addSectionHeader(layout, "🔊 Audio Enhancement")
        
        val audioEnhancementDesc = TextView(requireContext()).apply {
            text = "Advanced equalizer with 20+ presets including Super Bass Boost, Spatial Audio, and Professional Audio Effects. Configure in the Audio tab."
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_secondary))
            ResponsiveUtils.applyResponsiveTextSize(this, 14f)
            ResponsiveUtils.applyResponsivePadding(this, 0, 8, 0, 16)
        }
        layout.addView(audioEnhancementDesc)
        
        // Performance Section
        addSectionHeader(layout, "⚙️ Performance Settings")
        
        val performanceModeSpinner = Spinner(requireContext())
        val performanceModes = listOf(
            "Balanced" to "balanced",
            "High Performance" to "high_performance", 
            "Battery Saver" to "battery_saver"
        )
        val performanceAdapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, performanceModes.map { it.first })
        performanceAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        performanceModeSpinner.adapter = performanceAdapter
        
        val currentMode = synthwavePrefs.getString("performance_mode", "balanced")
        performanceModeSpinner.setSelection(performanceModes.indexOfFirst { it.second == currentMode }.coerceAtLeast(0))
        
        performanceModeSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val selectedMode = performanceModes[position].second
                synthwavePrefs.edit().putString("performance_mode", selectedMode).apply()
                Toast.makeText(requireContext(), "Performance mode: ${performanceModes[position].first}", Toast.LENGTH_SHORT).show()
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        layout.addView(performanceModeSpinner)
        
        // Feature Status Section
        addSectionHeader(layout, "✅ Feature Status")
        
        val featureStatus = TextView(requireContext()).apply {
            text = """✅ Enhanced SynthWave Visualizer - Active
✅ Animation Settings Panel - Available
✅ Visual Customization - Available
✅ Advanced Equalizer - 20+ Presets
✅ Photo Backgrounds - With Effects
✅ Performance Optimization - Enabled"""
            setTextColor(ContextCompat.getColor(requireContext(), com.stash.opusplayer.R.color.text_secondary))
            ResponsiveUtils.applyResponsiveTextSize(this, 12f)
            typeface = android.graphics.Typeface.MONOSPACE
        }
        layout.addView(featureStatus)
        
        scrollView.addView(layout)
        ResponsiveUtils.applyResponsiveDesign(layout)
        
        return scrollView
    }
}
