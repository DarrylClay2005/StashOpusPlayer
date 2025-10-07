package com.stash.opusplayer.ui.appearance

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import com.stash.opusplayer.R
import com.stash.opusplayer.ui.MainActivity

class AppearanceFragment : Fragment() {
    
    private var currentPrefs = AppearancePreferences()
    private lateinit var previewCard: MaterialCardView
    private lateinit var previewTitle: TextView
    private lateinit var previewBody: TextView
    private lateinit var previewButton: MaterialButton
    
    // Color tracking for preview updates
    private var tempPrimaryColor: Int? = null
    private var tempAccentColor: Int? = null
    private var tempBackgroundColor: Int? = null
    private var tempTextPrimaryColor: Int? = null
    private var tempTextSecondaryColor: Int? = null
    
    // File picker launchers
    private val exportLauncher = registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        uri?.let { exportPresetToUri(it) }
    }
    
    private val importLauncher = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { importPresetFromUri(it) }
    }
    
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        currentPrefs = AppearancePreferences.fromPrefs(requireContext())
        return createAppearanceView()
    }
    
    private fun createAppearanceView(): View {
        val scrollView = ScrollView(requireContext())
        val layout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        
        // Title
        val title = TextView(requireContext()).apply {
            text = getString(R.string.settings_appearance_title)
            textSize = 24f
            setPadding(0, 0, 0, 32)
            setTextColor(ContextCompat.getColor(requireContext(), R.color.text_primary))
        }
        layout.addView(title)
        
        // Live Preview Card
        layout.addView(buildLivePreviewCard())
        
        // Theme & Colors Section
        addSectionHeader(layout, getString(R.string.settings_appearance_theme_colors))
        layout.addView(buildThemeColorsSection())
        
        // Typography Section
        addSectionHeader(layout, getString(R.string.settings_appearance_typography))
        layout.addView(buildTypographySection())
        
        // UI Elements Section
        addSectionHeader(layout, getString(R.string.settings_appearance_ui_elements))
        layout.addView(buildUIElementsSection())
        
        // Background Section
        addSectionHeader(layout, getString(R.string.settings_appearance_background))
        layout.addView(buildBackgroundSection())
        
        // Animations Section
        addSectionHeader(layout, getString(R.string.settings_appearance_animations))
        layout.addView(buildAnimationsSection())
        
        // Mini Player Section
        addSectionHeader(layout, getString(R.string.settings_appearance_mini_player))
        layout.addView(buildMiniPlayerSection())
        
        // SynthWave Visualizer Section
        addSectionHeader(layout, "SynthWave Visualizer")
        layout.addView(buildSynthWaveSection())
        
        // Presets Section
        addSectionHeader(layout, getString(R.string.settings_appearance_presets))
        layout.addView(buildPresetsSection())
        
        // Global Reset Button
        val resetAllButton = MaterialButton(requireContext()).apply {
            text = getString(R.string.appearance_reset_defaults)
            setTextColor(Color.WHITE)
            backgroundTintList = android.content.res.ColorStateList.valueOf(ContextCompat.getColor(requireContext(), R.color.error_color))
            setOnClickListener { showResetAllDialog() }
        }
        layout.addView(resetAllButton)
        
        scrollView.addView(layout)
        return scrollView
    }
    
    private fun buildLivePreviewCard(): View {
        val container = FrameLayout(requireContext()).apply {
            setPadding(0, 0, 0, 24)
        }
        
        previewCard = MaterialCardView(requireContext()).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            )
            radius = currentPrefs.cardCornerRadiusDp * resources.displayMetrics.density
            setCardBackgroundColor(currentPrefs.backgroundColor)
            cardElevation = if (currentPrefs.shadowsEnabled) 8f * currentPrefs.shadowIntensity else 0f
        }
        
        val innerLayout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 24)
        }
        
        previewTitle = TextView(requireContext()).apply {
            text = getString(R.string.appearance_live_preview)
            textSize = 18f * currentPrefs.fontScale
            setTextColor(currentPrefs.textPrimaryColor)
            typeface = if (currentPrefs.titleBold) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
        }
        innerLayout.addView(previewTitle)
        
        previewBody = TextView(requireContext()).apply {
            text = "This preview updates in real-time as you adjust settings"
            textSize = 14f * currentPrefs.fontScale
            setTextColor(currentPrefs.textSecondaryColor)
            setPadding(0, 8, 0, 16)
        }
        innerLayout.addView(previewBody)
        
        previewButton = MaterialButton(requireContext()).apply {
            text = "Sample Button"
            backgroundTintList = android.content.res.ColorStateList.valueOf(currentPrefs.accentColor)
            setTextColor(Color.WHITE)
            scaleX = currentPrefs.buttonSizeScale
            scaleY = currentPrefs.buttonSizeScale
        }
        innerLayout.addView(previewButton)
        
        previewCard.addView(innerLayout)
        container.addView(previewCard)
        return container
    }
    
    private fun buildThemeColorsSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Quick presets chips
        val presetsLabel = TextView(requireContext()).apply {
            text = getString(R.string.appearance_presets_quick)
            setTextColor(ContextCompat.getColor(requireContext(), R.color.text_secondary))
            setPadding(0, 8, 0, 8)
        }
        section.addView(presetsLabel)
        
        val chipGroup = ChipGroup(requireContext()).apply {
            isSingleSelection = false
        }
        
        AppearancePresets.listPresets().forEach { preset ->
            val chip = Chip(requireContext()).apply {
                text = preset.name
                isCheckable = true
                setOnClickListener {
                    applyPreset(preset)
                    isChecked = false
                }
            }
            chipGroup.addView(chip)
        }
        section.addView(chipGroup)
        
        // Color pickers
        section.addView(createColorPickerButton(getString(R.string.appearance_primary_color), currentPrefs.primaryColor) { color ->
            tempPrimaryColor = color
            updatePreview()
        })
        
        section.addView(createColorPickerButton(getString(R.string.appearance_accent_color), currentPrefs.accentColor) { color ->
            tempAccentColor = color
            updatePreview()
        })
        
        section.addView(createColorPickerButton(getString(R.string.appearance_background_color), currentPrefs.backgroundColor) { color ->
            tempBackgroundColor = color
            updatePreview()
            checkContrast()
        })
        
        section.addView(createColorPickerButton(getString(R.string.appearance_text_primary_color), currentPrefs.textPrimaryColor) { color ->
            tempTextPrimaryColor = color
            updatePreview()
            checkContrast()
        })
        
        section.addView(createColorPickerButton(getString(R.string.appearance_text_secondary_color), currentPrefs.textSecondaryColor) { color ->
            tempTextSecondaryColor = color
            updatePreview()
            checkContrast()
        })
        
        // Apply Colors Button
        val applyButton = MaterialButton(requireContext()).apply {
            text = getString(R.string.appearance_apply_colors)
            setOnClickListener { applyColors() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 16, 0, 0)
            }
        }
        section.addView(applyButton)
        
        return section
    }
    
    private fun buildTypographySection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Font scale spinner
        val fontScaleLabel = TextView(requireContext()).apply {
            text = getString(R.string.appearance_font_scale)
            setTextColor(ContextCompat.getColor(requireContext(), R.color.text_secondary))
            setPadding(0, 8, 0, 8)
        }
        section.addView(fontScaleLabel)
        
        val fontScales = listOf(
            getString(R.string.appearance_font_scale_small) to 0.85f,
            getString(R.string.appearance_font_scale_medium) to 1.0f,
            getString(R.string.appearance_font_scale_large) to 1.15f,
            getString(R.string.appearance_font_scale_xlarge) to 1.3f
        )
        
        val fontScaleSpinner = Spinner(requireContext())
        val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, fontScales.map { it.first })
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        fontScaleSpinner.adapter = adapter
        fontScaleSpinner.setSelection(fontScales.indexOfFirst { it.second == currentPrefs.fontScale }.coerceAtLeast(0))
        fontScaleSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val newScale = fontScales[position].second
                currentPrefs = currentPrefs.copy(fontScale = newScale)
                currentPrefs.saveToPrefs(requireContext())
                updatePreview()
                ThemeManager.broadcastChange(requireContext(), true) // Requires recreate
                Toast.makeText(requireContext(), "Font scale changed. App will restart.", Toast.LENGTH_SHORT).show()
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        section.addView(fontScaleSpinner)
        
        // Bold titles toggle
        val boldToggle = CheckBox(requireContext()).apply {
            text = getString(R.string.appearance_title_weight_bold)
            isChecked = currentPrefs.titleBold
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(titleBold = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                updatePreview()
                ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        section.addView(boldToggle)
        
        return section
    }
    
    private fun buildUIElementsSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Button size scale
        section.addView(createSeekBarControl(
            getString(R.string.appearance_button_size),
            (currentPrefs.buttonSizeScale * 100).toInt(),
            80, 120,
            { progress ->
                val scale = progress / 100f
                previewButton.scaleX = scale
                previewButton.scaleY = scale
            },
            { progress ->
                val scale = progress / 100f
                currentPrefs = currentPrefs.copy(buttonSizeScale = scale)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        ))
        
        // Corner radius
        section.addView(createSeekBarControl(
            getString(R.string.appearance_corner_radius),
            currentPrefs.cardCornerRadiusDp,
            8, 32,
            { progress ->
                previewCard.radius = progress * resources.displayMetrics.density
            },
            { progress ->
                currentPrefs = currentPrefs.copy(cardCornerRadiusDp = progress)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        ))
        
        // Shadows enabled
        val shadowsToggle = CheckBox(requireContext()).apply {
            text = getString(R.string.appearance_shadows_enable)
            isChecked = currentPrefs.shadowsEnabled
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(shadowsEnabled = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                updatePreview()
                ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        section.addView(shadowsToggle)
        
        // Shadow intensity
        section.addView(createSeekBarControl(
            getString(R.string.appearance_shadow_intensity),
            (currentPrefs.shadowIntensity * 100).toInt(),
            0, 100,
            { progress ->
                val intensity = progress / 100f
                previewCard.cardElevation = if (currentPrefs.shadowsEnabled) 8f * intensity else 0f
            },
            { progress ->
                val intensity = progress / 100f
                currentPrefs = currentPrefs.copy(shadowIntensity = intensity)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        ))
        
        return section
    }
    
    private fun buildBackgroundSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Background image button
        val bgImageButton = MaterialButton(requireContext()).apply {
            text = getString(R.string.appearance_background_image)
            setOnClickListener {
                (activity as? MainActivity)?.pickBackgroundImage()
            }
        }
        section.addView(bgImageButton)
        
        // Use solid color toggle
        val solidColorToggle = CheckBox(requireContext()).apply {
            text = getString(R.string.appearance_use_solid_color)
            isChecked = currentPrefs.useSolidBackgroundColor
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(useSolidBackgroundColor = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
                activity?.let { ThemeManager.applyBackgroundOverlay(it, currentPrefs) }
            }
        }
        section.addView(solidColorToggle)
        
        // Background blur
        section.addView(createSeekBarControl(
            getString(R.string.appearance_background_blur) + " (Android 12+)",
            currentPrefs.backgroundBlurRadius,
            0, 25,
            { },
            { progress ->
                currentPrefs = currentPrefs.copy(backgroundBlurRadius = progress)
                currentPrefs.saveToPrefs(requireContext())
                activity?.let { ThemeManager.applyBackgroundOverlay(it, currentPrefs) }
                ThemeManager.broadcastChange(requireContext(), false)
            }
        ))
        
        // Background dim
        section.addView(createSeekBarControl(
            getString(R.string.appearance_background_dim),
            currentPrefs.backgroundDimPercent,
            0, 100,
            { },
            { progress ->
                currentPrefs = currentPrefs.copy(backgroundDimPercent = progress)
                currentPrefs.saveToPrefs(requireContext())
                activity?.let { ThemeManager.applyBackgroundOverlay(it, currentPrefs) }
                ThemeManager.broadcastChange(requireContext(), false)
            }
        ))
        
        return section
    }
    
    private fun buildAnimationsSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Enable animations
        val animToggle = CheckBox(requireContext()).apply {
            text = getString(R.string.appearance_animations_enable)
            isChecked = currentPrefs.animationsEnabled
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(animationsEnabled = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        section.addView(animToggle)
        
        // Animation speed
        val speedLabel = TextView(requireContext()).apply {
            text = getString(R.string.appearance_animation_speed)
            setTextColor(ContextCompat.getColor(requireContext(), R.color.text_secondary))
            setPadding(0, 16, 0, 8)
        }
        section.addView(speedLabel)
        
        val speeds = listOf(
            getString(R.string.appearance_animation_speed_slow) to AppearancePreferences.AnimationSpeed.SLOW,
            getString(R.string.appearance_animation_speed_normal) to AppearancePreferences.AnimationSpeed.NORMAL,
            getString(R.string.appearance_animation_speed_fast) to AppearancePreferences.AnimationSpeed.FAST
        )
        
        val speedSpinner = Spinner(requireContext())
        val speedAdapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, speeds.map { it.first })
        speedAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        speedSpinner.adapter = speedAdapter
        speedSpinner.setSelection(speeds.indexOfFirst { it.second == currentPrefs.animationSpeed }.coerceAtLeast(0))
        speedSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val newSpeed = speeds[position].second
                currentPrefs = currentPrefs.copy(animationSpeed = newSpeed)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        section.addView(speedSpinner)
        
        return section
    }
    
    private fun buildMiniPlayerSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Height
        section.addView(createSeekBarControl(
            getString(R.string.appearance_mini_player_height),
            currentPrefs.miniPlayerHeightDp,
            56, 96,
            { },
            { progress ->
                currentPrefs = currentPrefs.copy(miniPlayerHeightDp = progress)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        ))
        
        // Show album art
        val artToggle = CheckBox(requireContext()).apply {
            text = getString(R.string.appearance_mini_player_show_art)
            isChecked = currentPrefs.miniPlayerShowArt
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(miniPlayerShowArt = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        section.addView(artToggle)
        
        // Show artist name
        val artistToggle = CheckBox(requireContext()).apply {
            text = getString(R.string.appearance_mini_player_show_artist)
            isChecked = currentPrefs.miniPlayerShowArtist
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(miniPlayerShowArtist = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        section.addView(artistToggle)
        
        // Compact mode
        val compactToggle = CheckBox(requireContext()).apply {
            text = getString(R.string.appearance_mini_player_compact_mode)
            isChecked = currentPrefs.miniPlayerCompactMode
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(miniPlayerCompactMode = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        section.addView(compactToggle)
        
        // Spinning art animation
        val spinningArtToggle = CheckBox(requireContext()).apply {
            text = getString(R.string.appearance_mini_player_spinning_art)
            isChecked = currentPrefs.miniPlayerSpinningArt
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(miniPlayerSpinningArt = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
            }
        }
        section.addView(spinningArtToggle)
        
        return section
    }
    
    private fun buildSynthWaveSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Progress mode toggle
        val progressModeToggle = CheckBox(requireContext()).apply {
            text = "Progress Mode (Wave follows song progress)"
            isChecked = currentPrefs.synthWaveProgressMode
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(synthWaveProgressMode = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
                Toast.makeText(requireContext(), "SynthWave mode updated", Toast.LENGTH_SHORT).show()
            }
        }
        section.addView(progressModeToggle)
        
        // Custom colors toggle
        val customColorsToggle = CheckBox(requireContext()).apply {
            text = "Use Custom Colors"
            isChecked = currentPrefs.synthWaveUseCustomColors
            setOnCheckedChangeListener { _, isChecked ->
                currentPrefs = currentPrefs.copy(synthWaveUseCustomColors = isChecked)
                currentPrefs.saveToPrefs(requireContext())
                ThemeManager.broadcastChange(requireContext(), false)
                Toast.makeText(requireContext(), "SynthWave colors updated", Toast.LENGTH_SHORT).show()
            }
        }
        section.addView(customColorsToggle)
        
        // Custom color pickers (only show when custom colors is enabled)
        val colorSection = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            visibility = if (currentPrefs.synthWaveUseCustomColors) View.VISIBLE else View.GONE
        }
        
        colorSection.addView(createColorPickerButton("Primary Wave Color", currentPrefs.synthWavePrimaryColor) { color ->
            currentPrefs = currentPrefs.copy(synthWavePrimaryColor = color)
            currentPrefs.saveToPrefs(requireContext())
            ThemeManager.broadcastChange(requireContext(), false)
        })
        
        colorSection.addView(createColorPickerButton("Secondary Wave Color", currentPrefs.synthWaveSecondaryColor) { color ->
            currentPrefs = currentPrefs.copy(synthWaveSecondaryColor = color)
            currentPrefs.saveToPrefs(requireContext())
            ThemeManager.broadcastChange(requireContext(), false)
        })
        
        colorSection.addView(createColorPickerButton("Glow Color", currentPrefs.synthWaveGlowColor) { color ->
            currentPrefs = currentPrefs.copy(synthWaveGlowColor = color)
            currentPrefs.saveToPrefs(requireContext())
            ThemeManager.broadcastChange(requireContext(), false)
        })
        
        section.addView(colorSection)
        
        // Update color section visibility when custom colors toggle changes
        customColorsToggle.setOnCheckedChangeListener { _, isChecked ->
            currentPrefs = currentPrefs.copy(synthWaveUseCustomColors = isChecked)
            currentPrefs.saveToPrefs(requireContext())
            colorSection.visibility = if (isChecked) View.VISIBLE else View.GONE
            ThemeManager.broadcastChange(requireContext(), false)
            Toast.makeText(requireContext(), "SynthWave colors updated", Toast.LENGTH_SHORT).show()
        }
        
        return section
    }
    
    private fun buildPresetsSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Save preset button
        val saveButton = MaterialButton(requireContext()).apply {
            text = getString(R.string.appearance_save_preset)
            setOnClickListener { showSavePresetDialog() }
        }
        section.addView(saveButton)
        
        // Load preset button
        val loadButton = MaterialButton(requireContext()).apply {
            text = getString(R.string.appearance_load_preset)
            setOnClickListener { showLoadPresetDialog() }
        }
        section.addView(loadButton)
        
        // Export preset button
        val exportButton = MaterialButton(requireContext()).apply {
            text = getString(R.string.appearance_export_preset)
            setOnClickListener { exportPreset() }
        }
        section.addView(exportButton)
        
        // Import preset button
        val importButton = MaterialButton(requireContext()).apply {
            text = getString(R.string.appearance_import_preset)
            setOnClickListener { importPreset() }
        }
        section.addView(importButton)
        
        return section
    }
    
    // Helper methods continued in next part...
    private fun addSectionHeader(parent: LinearLayout, title: String) {
        val header = TextView(requireContext()).apply {
            text = title
            textSize = 18f
            setPadding(0, 24, 0, 12)
            setTextColor(ContextCompat.getColor(requireContext(), android.R.color.holo_blue_bright))
        }
        parent.addView(header)
    }
    
    private fun createColorPickerButton(label: String, initialColor: Int, onColorSelected: (Int) -> Unit): View {
        val row = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 8, 0, 8)
        }
        
        val labelView = TextView(requireContext()).apply {
            text = label
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            setTextColor(ContextCompat.getColor(requireContext(), R.color.text_primary))
        }
        row.addView(labelView)
        
        val colorSwatch = View(requireContext()).apply {
            val size = (48 * resources.displayMetrics.density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size)
            background = GradientDrawable().apply {
                setColor(initialColor)
                cornerRadius = 8 * resources.displayMetrics.density
                setStroke(2, ContextCompat.getColor(requireContext(), R.color.text_secondary))
            }
            setOnClickListener {
                val dialog = ColorPickerDialog.newInstance(initialColor) { color ->
                    (background as GradientDrawable).setColor(color)
                    onColorSelected(color)
                }
                dialog.show(parentFragmentManager, "color_picker")
            }
        }
        row.addView(colorSwatch)
        
        return row
    }
    
    private fun createSeekBarControl(
        label: String,
        initialValue: Int,
        min: Int,
        max: Int,
        onProgressChange: (Int) -> Unit,
        onProgressStop: (Int) -> Unit
    ): View {
        val container = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 8, 0, 8)
        }
        
        val labelView = TextView(requireContext()).apply {
            text = "$label: $initialValue"
            setTextColor(ContextCompat.getColor(requireContext(), R.color.text_secondary))
        }
        container.addView(labelView)
        
        val seekBar = SeekBar(requireContext()).apply {
            this.max = max - min
            progress = initialValue - min
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    val value = progress + min
                    labelView.text = "$label: $value"
                    if (fromUser) {
                        onProgressChange(value)
                    }
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {
                    val value = (seekBar?.progress ?: 0) + min
                    onProgressStop(value)
                }
            })
        }
        container.addView(seekBar)
        
        return container
    }
    
    private fun updatePreview() {
        val primaryColor = tempPrimaryColor ?: currentPrefs.primaryColor
        val accentColor = tempAccentColor ?: currentPrefs.accentColor
        val backgroundColor = tempBackgroundColor ?: currentPrefs.backgroundColor
        val textPrimary = tempTextPrimaryColor ?: currentPrefs.textPrimaryColor
        val textSecondary = tempTextSecondaryColor ?: currentPrefs.textSecondaryColor
        
        previewCard.setCardBackgroundColor(backgroundColor)
        previewTitle.setTextColor(textPrimary)
        previewTitle.textSize = 18f * currentPrefs.fontScale
        previewTitle.typeface = if (currentPrefs.titleBold) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
        previewBody.setTextColor(textSecondary)
        previewBody.textSize = 14f * currentPrefs.fontScale
        previewButton.backgroundTintList = android.content.res.ColorStateList.valueOf(accentColor)
    }
    
    private fun applyColors() {
        currentPrefs = currentPrefs.copy(
            primaryColor = tempPrimaryColor ?: currentPrefs.primaryColor,
            accentColor = tempAccentColor ?: currentPrefs.accentColor,
            backgroundColor = tempBackgroundColor ?: currentPrefs.backgroundColor,
            textPrimaryColor = tempTextPrimaryColor ?: currentPrefs.textPrimaryColor,
            textSecondaryColor = tempTextSecondaryColor ?: currentPrefs.textSecondaryColor
        )
        currentPrefs.saveToPrefs(requireContext())
        ThemeManager.broadcastChange(requireContext(), false)
        Toast.makeText(requireContext(), R.string.toast_applied, Toast.LENGTH_SHORT).show()
    }
    
    private fun applyPreset(preset: AppearancePresets.PresetInfo) {
        tempPrimaryColor = preset.primaryColor
        tempAccentColor = preset.accentColor
        tempBackgroundColor = preset.backgroundColor
        tempTextPrimaryColor = preset.textPrimaryColor
        tempTextSecondaryColor = preset.textSecondaryColor
        updatePreview()
        Toast.makeText(requireContext(), "Preset applied. Click 'Apply Colors' to save.", Toast.LENGTH_SHORT).show()
    }
    
    private fun checkContrast() {
        val bg = tempBackgroundColor ?: currentPrefs.backgroundColor
        val textPrimary = tempTextPrimaryColor ?: currentPrefs.textPrimaryColor
        
        val ratio = currentPrefs.calculateContrastRatio(textPrimary, bg)
        if (ratio < 4.5) {
            Toast.makeText(requireContext(), R.string.tooltip_contrast_warning, Toast.LENGTH_LONG).show()
        }
    }
    
    private fun showSavePresetDialog() {
        val input = EditText(requireContext()).apply {
            hint = getString(R.string.appearance_preset_name_hint)
        }
        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.appearance_save_preset))
            .setView(input)
            .setPositiveButton("Save") { _, _ ->
                val name = input.text.toString().trim()
                if (name.isNotEmpty()) {
                    if (AppearancePresets.customPresetExists(requireContext(), name)) {
                        confirmOverwritePreset(name)
                    } else {
                        AppearancePresets.saveCustomPreset(requireContext(), name, currentPrefs)
                        Toast.makeText(requireContext(), R.string.toast_saved, Toast.LENGTH_SHORT).show()
                    }
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
    
    private fun confirmOverwritePreset(name: String) {
        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle("Overwrite Preset?")
            .setMessage("A preset with this name already exists. Overwrite it?")
            .setPositiveButton("Overwrite") { _, _ ->
                AppearancePresets.saveCustomPreset(requireContext(), name, currentPrefs)
                Toast.makeText(requireContext(), R.string.toast_saved, Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
    
    private fun showLoadPresetDialog() {
        val presets = AppearancePresets.getCustomPresetNames(requireContext())
        if (presets.isEmpty()) {
            Toast.makeText(requireContext(), "No saved presets", Toast.LENGTH_SHORT).show()
            return
        }
        
        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.appearance_load_preset))
            .setItems(presets.toTypedArray()) { _, which ->
                val name = presets[which]
                AppearancePresets.loadCustomPreset(requireContext(), name)?.let { prefs ->
                    currentPrefs = prefs
                    currentPrefs.saveToPrefs(requireContext())
                    updatePreview()
                    ThemeManager.broadcastChange(requireContext(), true)
                    Toast.makeText(requireContext(), R.string.toast_applied, Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
    
    private fun exportPreset() {
        exportLauncher.launch("appearance_preset.json")
    }
    
    private fun exportPresetToUri(uri: android.net.Uri) {
        try {
            requireContext().contentResolver.openOutputStream(uri)?.use { output ->
                output.write(currentPrefs.toJson().toByteArray())
            }
            Toast.makeText(requireContext(), R.string.toast_export_success, Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(requireContext(), R.string.toast_error, Toast.LENGTH_SHORT).show()
        }
    }
    
    private fun importPreset() {
        importLauncher.launch(arrayOf("application/json"))
    }
    
    private fun importPresetFromUri(uri: android.net.Uri) {
        try {
            val json = requireContext().contentResolver.openInputStream(uri)?.use { input ->
                input.bufferedReader().readText()
            } ?: return
            
            val prefs = AppearancePreferences.fromJson(json)
            currentPrefs = prefs
            currentPrefs.saveToPrefs(requireContext())
            updatePreview()
            ThemeManager.broadcastChange(requireContext(), true)
            Toast.makeText(requireContext(), R.string.toast_import_success, Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(requireContext(), "${getString(R.string.toast_error)}: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }
    
    private fun showResetAllDialog() {
        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.appearance_reset_defaults))
            .setMessage(getString(R.string.appearance_confirm_reset_all))
            .setPositiveButton("Reset") { _, _ ->
                AppearancePreferences.resetToDefaults(requireContext())
                currentPrefs = AppearancePreferences.fromPrefs(requireContext())
                updatePreview()
                ThemeManager.broadcastChange(requireContext(), true)
                activity?.recreate()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
}
