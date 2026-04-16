package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.text.InputType
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.fragment.app.Fragment
import com.stash.opusplayer.R
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.appearance.AppearanceFragment
import com.stash.opusplayer.ui.customization.VisualCustomizationFragment
import com.stash.opusplayer.ui.fragments.settings.LibrarySettingsFragment
import com.stash.opusplayer.ui.fragments.settings.PlaybackSettingsFragment
import com.stash.opusplayer.ui.fragments.settings.StreamingSettingsFragment
import com.stash.opusplayer.ui.fragments.settings.addActionButton
import com.stash.opusplayer.ui.fragments.settings.addBodyText
import com.stash.opusplayer.ui.fragments.settings.addChipButtonRow
import com.stash.opusplayer.ui.fragments.settings.addSettingsSection
import com.stash.opusplayer.ui.fragments.settings.addSettingsTile
import com.stash.opusplayer.ui.fragments.settings.addSpinnerControl
import com.stash.opusplayer.ui.fragments.settings.addSwitchControl
import com.stash.opusplayer.ui.fragments.settings.createSettingsPage
import com.stash.opusplayer.ui.fragments.settings.navigateToSettingsScreen
import com.stash.opusplayer.ui.fragments.settings.updateSettingsActionBar
import com.stash.opusplayer.updates.UpdateFrequency

class SettingsFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val (scrollView, content) = createSettingsPage(
            title = "Settings",
            subtitle = "A rebuilt settings hub for playback, library, streaming, visuals, maintenance, and updates."
        )

        buildQuickActions(content)
        buildCoreNavigation(content)
        buildUpdateControls(content)

        return scrollView
    }

    override fun onResume() {
        super.onResume()
        updateSettingsActionBar(getString(R.string.menu_settings), false)
    }

    private fun buildQuickActions(parent: LinearLayout) {
        parent.addView(TextView(requireContext()).apply {
            text = "Quick Actions"
            textSize = 18f
            setTextColor(androidx.core.content.ContextCompat.getColor(requireContext(), R.color.text_primary))
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, 0, 0, (8 * requireContext().resources.displayMetrics.density).toInt())
        })

        addChipButtonRow(
            parent,
            listOf(
                "Playback" to { openSettingsScreen(PlaybackSettingsFragment(), "Playback Settings") },
                "Appearance" to { openSettingsScreen(AppearanceFragment(), "Appearance") },
                "Motion" to { openSettingsScreen(VisualCustomizationFragment(), "Animations & Background") },
                "Rescan Library" to { startLibraryRescan() },
                "Check Updates" to { checkForUpdates(force = true) }
            )
        )
    }

    private fun buildCoreNavigation(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Core Areas",
            "Each card opens a focused screen instead of forcing everything through the old broken mega-fragment."
        )

        addSettingsTile(
            section,
            title = "Playback & Queue",
            summary = "Speed, pitch, reverb, crossfade, ReplayGain, and playback recovery tools."
        ) {
            openSettingsScreen(PlaybackSettingsFragment(), "Playback Settings")
        }

        addSettingsTile(
            section,
            title = "Audio Effects",
            summary = "Equalizer, bass boost, virtualizer, and loudness controls."
        ) {
            openSettingsScreen(EqualizerFragment(), "Equalizer")
        }

        addSettingsTile(
            section,
            title = "Appearance & Layout",
            summary = "Theme colors, mini-player styles, and now playing layout themes."
        ) {
            openSettingsScreen(AppearanceFragment(), "Appearance")
        }

        addSettingsTile(
            section,
            title = "Animations & Background",
            summary = "Stable animation controls, background mode presets, and photo tuning."
        ) {
            openSettingsScreen(VisualCustomizationFragment(), "Animations & Background")
        }

        addSettingsTile(
            section,
            title = "Library & Scanning",
            summary = "Folder access, default layouts, artwork cleanup, and scan scheduling."
        ) {
            openSettingsScreen(LibrarySettingsFragment(), "Library Settings")
        }

        addSettingsTile(
            section,
            title = "Streaming & Downloads",
            summary = "YouTube API key, Lavalink routing, extractor health, and yt-dlp updates."
        ) {
            openSettingsScreen(StreamingSettingsFragment(), "Streaming & Downloads")
        }
    }

    private fun buildUpdateControls(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Updates",
            "The update controls are now visible on the first screen instead of being buried inside the old general tab."
        )

        val updateManager = (activity as? MainActivity)?.getUpdateManager()
        val updatePreferences = updateManager?.getUpdatePreferences()

        addSwitchControl(
            section,
            title = "Automatic update checks",
            summary = "Let the app check in the background and decide when to surface new releases.",
            checked = updatePreferences?.autoCheckEnabled ?: true
        ) { enabled ->
            updateManager?.getUpdatePreferences()?.let {
                updateManager.updatePreferences(it.copy(autoCheckEnabled = enabled))
            }
        }

        val frequencySpinner = addSpinnerControl(
            section,
            title = "Check frequency",
            summary = "How often background checks should run when automatic updates are enabled.",
            entries = listOf("Daily", "Weekly", "Monthly", "Never")
        )
        val currentFrequency = updatePreferences?.checkFrequency ?: UpdateFrequency.DAILY
        val frequencyIndex = when (currentFrequency) {
            UpdateFrequency.DAILY -> 0
            UpdateFrequency.WEEKLY -> 1
            UpdateFrequency.MONTHLY -> 2
            UpdateFrequency.NEVER -> 3
        }
        var frequencyHydrated = false
        frequencySpinner.setSelection(frequencyIndex)
        frequencySpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!frequencyHydrated) {
                    frequencyHydrated = true
                    return
                }
                updateManager?.getUpdatePreferences()?.let {
                    val frequency = when (position) {
                        1 -> UpdateFrequency.WEEKLY
                        2 -> UpdateFrequency.MONTHLY
                        3 -> UpdateFrequency.NEVER
                        else -> UpdateFrequency.DAILY
                    }
                    updateManager?.updatePreferences(it.copy(checkFrequency = frequency))
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        addActionButton(section, "Check for updates now") {
            checkForUpdates(force = true)
        }
    }

    private fun openSettingsScreen(fragment: Fragment, title: String) {
        updateSettingsActionBar(title, true)
        navigateToSettingsScreen(fragment)
    }

    private fun startLibraryRescan() {
        runCatching {
            val request = androidx.work.OneTimeWorkRequestBuilder<com.stash.opusplayer.work.LibraryRescanWorker>().build()
            androidx.work.WorkManager.getInstance(requireContext()).enqueue(request)
            Toast.makeText(requireContext(), "Library rescan started.", Toast.LENGTH_SHORT).show()
        }.onFailure {
            Toast.makeText(requireContext(), "Unable to start a library rescan.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun checkForUpdates(force: Boolean) {
        runCatching {
            (activity as? MainActivity)?.getUpdateManager()?.checkForUpdates(requireActivity(), forceCheck = force)
        }.onFailure {
            Toast.makeText(requireContext(), "Update check could not be started.", Toast.LENGTH_SHORT).show()
        }
    }
}
