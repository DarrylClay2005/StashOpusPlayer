package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import androidx.fragment.app.Fragment
import android.widget.*
import android.view.View
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.updates.UpdatePreferences

class SettingsFragment : Fragment() {
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
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
            setOnClickListener {
                (activity as? MainActivity)?.pickBackgroundImage()
            }
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

        // Online Artwork Section
        addSectionHeader(layout, "Album Artwork")
        val artworkToggle = CheckBox(requireContext()).apply {
            text = "Fetch album art online when missing"
            isChecked = true
            setOnCheckedChangeListener { _, isChecked ->
                // Persist in shared preferences for now (simple)
                val prefs = requireContext().getSharedPreferences("settings", 0)
                prefs.edit().putBoolean("fetch_artwork_online", isChecked).apply()
            }
        }
        layout.addView(artworkToggle)
        
        val providerHint = TextView(requireContext()).apply {
            text = "Uses MusicBrainz + Cover Art Archive with iTunes fallback."
            textSize = 12f
        }
        layout.addView(providerHint)
        
        // Check frequency
        val frequencyLabel = TextView(requireContext()).apply {
            text = "Check frequency:"
            setPadding(0, 20, 0, 8)
        }
        layout.addView(frequencyLabel)
        
        val frequencySpinner = Spinner(requireContext()).apply {
            val frequencies = arrayOf("Daily", "Weekly", "Monthly", "Never")
            val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, frequencies)
            adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            this.adapter = adapter
            
            val currentFreq = updatePrefs?.checkFrequency ?: 24L
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
                    val prefs = updateManager?.getUpdatePreferences()
                    if (prefs != null) {
                        updateManager.updatePreferences(
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
    
    private fun addSectionHeader(parent: LinearLayout, title: String) {
        val header = TextView(requireContext()).apply {
            text = title
            textSize = 18f
            setPadding(0, 24, 0, 12)
            setTextColor(ContextCompat.getColor(requireContext(), android.R.color.holo_blue_bright))
        }
        parent.addView(header)
    }
}
