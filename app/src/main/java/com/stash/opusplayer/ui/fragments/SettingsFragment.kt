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
            tabGravity = com.google.android.material.tabs.TabLayout.GRAVITY_FILL
        }
        root.addView(tabs, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

        val contentContainer = FrameLayout(requireContext()).apply { id = View.generateViewId() }
        root.addView(contentContainer, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.MATCH_PARENT))

        // Build the two pages as Views
        val generalView = buildGeneralContent()
        val pitchView = buildPitchContent() // Now includes Speed & Reverb too

        // Default to General tab
        contentContainer.addView(generalView)

        tabs.addOnTabSelectedListener(object : com.google.android.material.tabs.TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: com.google.android.material.tabs.TabLayout.Tab) {
                contentContainer.removeAllViews()
                when (tab.position) {
                    0 -> contentContainer.addView(generalView)
                    1 -> contentContainer.addView(pitchView)
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
            setPadding(32, 32, 32, 32)
        }

        // Title
        val titleText = TextView(requireContext()).apply {
            text = "Settings"
            textSize = 24f
            setPadding(0, 0, 0, 32)
        }
        layout.addView(titleText)

        // Background Settings Section
        addSectionHeader(layout, "Appearance")

        val backgroundButton = Button(requireContext()).apply {
            text = "Change Background Image"
            setOnClickListener { (activity as? MainActivity)?.pickBackgroundImage() }
        }
        layout.addView(backgroundButton)

        // Update Settings Section
        addSectionHeader(layout, "Updates")

        val updateManager = (activity as? MainActivity)?.getUpdateManager()
        val updatePrefs = updateManager?.getUpdatePreferences()

        // Auto-check updates toggle
        val autoCheckToggle = CheckBox(requireContext()).apply {
            text = "Automatically check for updates"
            isChecked = updatePrefs?.autoCheckEnabled ?: true
            setOnCheckedChangeListener { _, isChecked ->
                val prefs = updateManager?.getUpdatePreferences()
                if (prefs != null) {
                    updateManager.updatePreferences(
                        prefs.copy(autoCheckEnabled = isChecked)
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
                val prefs = requireContext().getSharedPreferences("settings", 0)
                prefs.edit().putBoolean("fetch_artwork_online", isChecked).apply()
            }
        }
        layout.addView(artworkToggle)

        val artistToggle = CheckBox(requireContext()).apply {
            text = "Fetch artist images online"
            isChecked = true
            setOnCheckedChangeListener { _, isChecked ->
                val prefs = requireContext().getSharedPreferences("settings", 0)
                prefs.edit().putBoolean("fetch_artist_images_online", isChecked).apply()
            }
        }
        layout.addView(artistToggle)

        val genreToggle = CheckBox(requireContext()).apply {
            text = "Fetch genre images online"
            isChecked = true
            setOnCheckedChangeListener { _, isChecked ->
                val prefs = requireContext().getSharedPreferences("settings", 0)
                prefs.edit().putBoolean("fetch_genre_images_online", isChecked).apply()
            }
        }
        layout.addView(genreToggle)

        val providerHint = TextView(requireContext()).apply {
            text = "Album: MusicBrainz + CAA + iTunes. Artist/Genre: Last.fm (if key) and Wikipedia fallback."
            textSize = 12f
        }
        layout.addView(providerHint)

        val apiKeyLabel = TextView(requireContext()).apply { text = "Last.fm API key (optional):" }
        layout.addView(apiKeyLabel)
        val apiKeyInput = EditText(requireContext()).apply {
            val prefs = requireContext().getSharedPreferences("settings", 0)
            setText(prefs.getString("lastfm_api_key", "") ?: "")
            hint = "Enter Last.fm API key"
        }
        layout.addView(apiKeyInput)
        val saveApiKeyBtn = Button(requireContext()).apply {
            text = "Save Last.fm API key"
            setOnClickListener {
                val prefs = requireContext().getSharedPreferences("settings", 0)
                prefs.edit().putString("lastfm_api_key", apiKeyInput.text.toString().trim()).apply()
                Toast.makeText(requireContext(), "Saved", Toast.LENGTH_SHORT).show()
            }
        }
        layout.addView(saveApiKeyBtn)

        // Music Folders Section
        addSectionHeader(layout, "Music Folders")
        val addFolderButton = Button(requireContext()).apply {
            text = "Add Folder (tree)"
            setOnClickListener { pickMusicFolder() }
        }
        layout.addView(addFolderButton)

        val currentFoldersLabel = TextView(requireContext()).apply {
            text = "Selected folders are used in Folders tab and library scans."
            textSize = 12f
        }
        layout.addView(currentFoldersLabel)

        val manageFoldersButton = Button(requireContext()).apply {
            text = "Manage Folders"
            setOnClickListener { showManageFoldersDialog() }
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
                val prefs = requireContext().getSharedPreferences("settings", 0)
                prefs.edit().putBoolean("enable_background_rescans", isChecked).apply()
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
            val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, frequencies)
            adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            this.adapter = adapter

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
                    val prefs = updateManager2?.getUpdatePreferences()
                    if (prefs != null) {
                        (activity as? MainActivity)?.getUpdateManager()?.updatePreferences(
                            prefs.copy(checkFrequency = frequency)
                        )
                    }
                }
                override fun onNothingSelected(parent: AdapterView<*>?) {}
            }
        }
        layout.addView(frequencySpinner)

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
        return scrollView
    }

    private fun buildPitchContent(): View {
        val scrollView = ScrollView(requireContext())
        val layout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }

        val title = TextView(requireContext()).apply {
            text = "Audio Controls"
            textSize = 22f
            setPadding(0, 0, 0, 16)
        }
        layout.addView(title)

        val desc = TextView(requireContext()).apply {
            text = "Adjust global audio: speed, pitch, and reverb. Applies live and persists across sessions."
            textSize = 14f
        }
        layout.addView(desc)

        val prefs = requireContext().getSharedPreferences("settings", 0)
        val savedSemitones = prefs.getInt("pitch_semitones", 0)

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
            prefs.edit().putInt("pitch_semitones", semi).putFloat("pitch_factor", pitch).apply()
            // Apply to running session if available
            mediaController?.let { controller ->
                try {
                    // Update controller params locally
                    val current = controller.playbackParameters
                    controller.playbackParameters = androidx.media3.common.PlaybackParameters(current.speed, pitch)
                } catch (_: Exception) {}
                try {
                    controller.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_PITCH", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("pitch" to pitch)
                    )
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

        val savedSpeed = prefs.getFloat("playback_speed", 1.0f)
        fun speedToProgress(sp: Float) = ((sp - 0.25f) * 100).toInt().coerceIn(0, 175) // 0.25..2.0
        fun progressToSpeed(p: Int) = 0.25f + (p.toFloat() / 100f)

        val speedSeek = SeekBar(requireContext()).apply {
            max = 175
            progress = speedToProgress(savedSpeed)
        }
        layout.addView(speedSeek)

        fun applySpeed(sp: Float) {
            // Persist
            prefs.edit().putFloat("playback_speed", sp).apply()
            speedLabel.text = String.format("%.2fx", sp)
            // Apply live
            mediaController?.let { controller ->
                try {
                    val cur = controller.playbackParameters
                    controller.playbackParameters = androidx.media3.common.PlaybackParameters(sp, cur.pitch)
                } catch (_: Exception) {}
                try {
                    controller.sendCustomCommand(
                        androidx.media3.session.SessionCommand("SET_SPEED", android.os.Bundle.EMPTY),
                        androidx.core.os.bundleOf("speed" to sp)
                    )
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

        val savedPreset = prefs.getInt("reverb_preset", 0)
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
            reverbLabel.text = "Reverb ${p / 10}%"
            val preset: Short = when {
                p < 50 -> 0
                p < 200 -> 1
                p < 400 -> 2
                p < 600 -> 3
                p < 800 -> 4
                p < 950 -> 5
                else -> 6
            }.toShort()
            prefs.edit().putInt("reverb_preset", preset.toInt()).apply()
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
                else reverbLabel.text = "Reverb ${progress / 10}%"
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        scrollView.addView(layout)
        return scrollView
    }
    
    private fun addSectionHeader(parent: LinearLayout, title: String) {
        val header = TextView(requireContext()).apply {
            text = title
            textSize = 18f
            setPadding(0, 24, 0, 12)
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

    private fun clearArtworkCache() {
        try {
            val dir = java.io.File(requireContext().cacheDir, "artwork")
            if (dir.exists()) {
                dir.listFiles()?.forEach { it.delete() }
            }
            Toast.makeText(requireContext(), "Artwork cache cleared", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {
            Toast.makeText(requireContext(), "Failed to clear cache", Toast.LENGTH_SHORT).show()
        }
    }
}
