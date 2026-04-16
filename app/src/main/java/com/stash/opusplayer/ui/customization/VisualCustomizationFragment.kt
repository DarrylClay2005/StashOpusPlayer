package com.stash.opusplayer.ui.customization

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import com.stash.opusplayer.ui.appearance.AppearancePreferences
import com.stash.opusplayer.ui.appearance.ThemeManager
import com.stash.opusplayer.ui.appearance.VisualCustomizationManager
import com.stash.opusplayer.ui.fragments.settings.NavigableSettingsFragment
import com.stash.opusplayer.ui.fragments.settings.addActionButton
import com.stash.opusplayer.ui.fragments.settings.addBodyText
import com.stash.opusplayer.ui.fragments.settings.addChipButtonRow
import com.stash.opusplayer.ui.fragments.settings.addSettingsSection
import com.stash.opusplayer.ui.fragments.settings.addSliderControl
import com.stash.opusplayer.ui.fragments.settings.addSpinnerControl
import com.stash.opusplayer.ui.fragments.settings.addSwitchControl
import com.stash.opusplayer.ui.fragments.settings.createSettingsPage
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

class VisualCustomizationFragment : NavigableSettingsFragment() {

    override val screenTitle: String = "Animations & Background"

    private lateinit var customizationManager: VisualCustomizationManager
    private lateinit var backgroundStatusView: TextView
    private lateinit var motionStatusView: TextView
    private lateinit var backgroundModeSpinner: Spinner
    private lateinit var animationSpeedSpinner: Spinner

    private var currentPrefs = AppearancePreferences()
    private var hydratingBackgroundMode = false
    private var hydratingAnimationSpeed = false

    private val imagePickerLauncher = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri == null) {
            syncUiFromState()
            return@registerForActivityResult
        }

        lifecycleScope.launch {
            val success = customizationManager.setPhotoBackground(uri)
            if (success) {
                broadcastLiveUpdate()
                Toast.makeText(requireContext(), "Background photo updated.", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(requireContext(), "Unable to load that image.", Toast.LENGTH_SHORT).show()
            }
            syncUiFromState()
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        customizationManager = VisualCustomizationManager(requireContext())
        currentPrefs = AppearancePreferences.fromPrefs(requireContext())

        val (scrollView, content) = createSettingsPage(
            title = "Animations & Background",
            subtitle = "This screen replaces the old animation tab with stable motion controls, dependable background presets, and smaller state surface area."
        )

        buildCurrentState(content)
        buildAnimationSection(content)
        buildBackgroundSection(content)
        buildPhotoSection(content)
        buildRecoverySection(content)
        syncUiFromState()

        return scrollView
    }

    private fun buildCurrentState(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Current State",
            "You can verify what the app is actually using here before leaving the screen."
        )

        backgroundStatusView = addBodyText(section, "")
        motionStatusView = addBodyText(section, "")
    }

    private fun buildAnimationSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "App Motion",
            "Only supported motion settings remain here now, which keeps animation changes from breaking the rest of the UI."
        )

        addSwitchControl(
            section,
            title = "Enable app animations",
            summary = "Turns the app’s extra movement on or off without affecting playback itself.",
            checked = currentPrefs.animationsEnabled
        ) { enabled ->
            persistAppearance(currentPrefs.copy(animationsEnabled = enabled))
        }

        val speeds = AppearancePreferences.AnimationSpeed.entries
        animationSpeedSpinner = addSpinnerControl(
            section,
            title = "Animation speed",
            summary = "Controls how quickly rebuilt UI transitions and motion helpers should run.",
            entries = listOf("Slow", "Normal", "Fast")
        )
        animationSpeedSpinner.setSelection(speeds.indexOf(currentPrefs.animationSpeed).coerceAtLeast(0))
        animationSpeedSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!hydratingAnimationSpeed) {
                    hydratingAnimationSpeed = true
                    return
                }
                val selected = speeds[position]
                if (selected != currentPrefs.animationSpeed) {
                    persistAppearance(currentPrefs.copy(animationSpeed = selected))
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        addSwitchControl(
            section,
            title = "Background parallax",
            summary = "Lets the background drift slightly with motion instead of staying completely static.",
            checked = customizationManager.isParallaxEnabled()
        ) { enabled ->
            customizationManager.setParallaxEnabled(enabled)
            broadcastLiveUpdate()
        }

        addSwitchControl(
            section,
            title = "Breathing background",
            summary = "Adds a slow ambient pulse to the background layer.",
            checked = customizationManager.isBreathingEnabled()
        ) { enabled ->
            customizationManager.setBreathingEnabled(enabled)
            broadcastLiveUpdate()
        }

        addSwitchControl(
            section,
            title = "Color shift",
            summary = "Allows subtle palette drifting in supported background effects.",
            checked = customizationManager.isColorShiftEnabled()
        ) { enabled ->
            customizationManager.setColorShiftEnabled(enabled)
            broadcastLiveUpdate()
        }
    }

    private fun buildBackgroundSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Background Mode",
            "Switch backgrounds safely here without falling back into the old unstable customization flow."
        )

        backgroundModeSpinner = addSpinnerControl(
            section,
            title = "Active background mode",
            summary = "Photo mode uses the selected image below. Gradient and solid color use the presets in this section.",
            entries = listOf("Gradient", "Solid Color", "Photo Background")
        )
        backgroundModeSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!hydratingBackgroundMode) {
                    hydratingBackgroundMode = true
                    return
                }

                when (position) {
                    1 -> setBackgroundMode(VisualCustomizationManager.BACKGROUND_TYPE_COLOR)
                    2 -> setBackgroundMode(VisualCustomizationManager.BACKGROUND_TYPE_PHOTO, launchPickerIfMissing = true)
                    else -> setBackgroundMode(VisualCustomizationManager.BACKGROUND_TYPE_GRADIENT)
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        addBodyText(section, "Gradient presets")
        addChipButtonRow(
            section,
            listOf(
                "Aurora" to {
                    customizationManager.setGradientBackground(0xFF2E1065.toInt(), 0xFF0F0F23.toInt())
                    syncUiFromState()
                    broadcastLiveUpdate()
                },
                "Ocean" to {
                    customizationManager.setGradientBackground(0xFF0B3C5D.toInt(), 0xFF081F2C.toInt())
                    syncUiFromState()
                    broadcastLiveUpdate()
                },
                "Ember" to {
                    customizationManager.setGradientBackground(0xFF5A1F08.toInt(), 0xFF1F0D08.toInt())
                    syncUiFromState()
                    broadcastLiveUpdate()
                }
            )
        )

        addBodyText(section, "Solid color presets")
        addChipButtonRow(
            section,
            listOf(
                "Charcoal" to {
                    customizationManager.setColorBackground(0xFF111827.toInt())
                    syncUiFromState()
                    broadcastLiveUpdate()
                },
                "Forest" to {
                    customizationManager.setColorBackground(0xFF10261B.toInt())
                    syncUiFromState()
                    broadcastLiveUpdate()
                },
                "Midnight" to {
                    customizationManager.setColorBackground(0xFF0D1B2A.toInt())
                    syncUiFromState()
                    broadcastLiveUpdate()
                }
            )
        )

        addActionButton(section, "Choose background photo") {
            imagePickerLauncher.launch("image/*")
        }

        addActionButton(section, "Clear background photo", outlined = true) {
            customizationManager.clearPhotoBackground()
            broadcastLiveUpdate()
            syncUiFromState()
            Toast.makeText(requireContext(), "Background photo cleared.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun buildPhotoSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Photo Tuning",
            "These sliders affect photo backgrounds only, but they stay saved so the mode works correctly when you switch back."
        )

        addSliderControl(
            section,
            title = "Blur amount",
            summary = "Softens busy photos so the app content stays readable.",
            valueFrom = 0f,
            valueTo = 25f,
            stepSize = 1f,
            initialValue = customizationManager.getPhotoBlurRadius().toFloat(),
            formatter = { "${it.roundToInt()} px" }
        ) { value, fromUser ->
            if (fromUser) {
                customizationManager.updatePhotoPresentation(blurRadius = value.roundToInt())
                broadcastLiveUpdate()
            }
        }

        addSliderControl(
            section,
            title = "Dim amount",
            summary = "Darkens the selected photo so text and controls remain legible.",
            valueFrom = 0f,
            valueTo = 70f,
            stepSize = 1f,
            initialValue = customizationManager.getPhotoDimming().toFloat(),
            formatter = { "${it.roundToInt()}%" }
        ) { value, fromUser ->
            if (fromUser) {
                customizationManager.updatePhotoPresentation(dimming = value.roundToInt())
                broadcastLiveUpdate()
            }
        }

        addSliderControl(
            section,
            title = "Photo opacity",
            summary = "Controls how strongly the image shows through the app surface.",
            valueFrom = 40f,
            valueTo = 100f,
            stepSize = 1f,
            initialValue = customizationManager.getPhotoOpacity().toFloat(),
            formatter = { "${it.roundToInt()}%" }
        ) { value, fromUser ->
            if (fromUser) {
                customizationManager.updatePhotoPresentation(opacity = value.roundToInt())
                broadcastLiveUpdate()
            }
        }
    }

    private fun buildRecoverySection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Recovery",
            "These buttons clear out shaky old state without forcing you to reinstall or wipe the whole app."
        )

        addActionButton(section, "Reset motion defaults") {
            customizationManager.resetMotionDefaults()
            persistAppearance(
                currentPrefs.copy(
                    animationsEnabled = true,
                    animationSpeed = AppearancePreferences.AnimationSpeed.NORMAL
                )
            )
            Toast.makeText(requireContext(), "Motion defaults restored.", Toast.LENGTH_SHORT).show()
        }

        addActionButton(section, "Reset background defaults", outlined = true) {
            customizationManager.resetBackgroundDefaults(clearPhoto = false)
            broadcastLiveUpdate()
            syncUiFromState()
            Toast.makeText(requireContext(), "Background defaults restored.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun persistAppearance(updatedPrefs: AppearancePreferences) {
        currentPrefs = updatedPrefs
        currentPrefs.saveToPrefs(requireContext())
        broadcastLiveUpdate()
    }

    private fun setBackgroundMode(mode: String, launchPickerIfMissing: Boolean = false) {
        if (mode == VisualCustomizationManager.BACKGROUND_TYPE_PHOTO && !customizationManager.hasPhotoBackground()) {
            if (launchPickerIfMissing) {
                imagePickerLauncher.launch("image/*")
            } else {
                Toast.makeText(requireContext(), "Choose a photo first.", Toast.LENGTH_SHORT).show()
            }
            syncUiFromState()
            return
        }

        customizationManager.setBackgroundType(mode)
        broadcastLiveUpdate()
        syncUiFromState()
    }

    private fun broadcastLiveUpdate() {
        ThemeManager.broadcastChange(requireContext(), false)
        refreshStatus()
    }

    private fun syncUiFromState() {
        currentPrefs = AppearancePreferences.fromPrefs(requireContext())

        hydratingBackgroundMode = false
        backgroundModeSpinner.setSelection(
            when (customizationManager.getBackgroundType()) {
                VisualCustomizationManager.BACKGROUND_TYPE_COLOR -> 1
                VisualCustomizationManager.BACKGROUND_TYPE_PHOTO -> 2
                else -> 0
            }
        )

        hydratingAnimationSpeed = false
        animationSpeedSpinner.setSelection(
            AppearancePreferences.AnimationSpeed.entries.indexOf(currentPrefs.animationSpeed).coerceAtLeast(0)
        )

        refreshStatus()
    }

    private fun refreshStatus() {
        val backgroundMode = when (customizationManager.getBackgroundType()) {
            VisualCustomizationManager.BACKGROUND_TYPE_COLOR -> "Solid color"
            VisualCustomizationManager.BACKGROUND_TYPE_PHOTO -> if (customizationManager.hasPhotoBackground()) "Photo background loaded" else "Photo mode needs an image"
            else -> "Gradient background"
        }

        backgroundStatusView.text = buildString {
            append("$backgroundMode")
            append(" • Blur ${customizationManager.getPhotoBlurRadius()}px")
            append(" • Dim ${customizationManager.getPhotoDimming()}%")
            append(" • Opacity ${customizationManager.getPhotoOpacity()}%")
        }

        motionStatusView.text = buildString {
            append("Animations ${if (currentPrefs.animationsEnabled) "On" else "Off"}")
            append(" • ${currentPrefs.animationSpeed.name.lowercase().replaceFirstChar { it.uppercase() }} speed")
            append(" • Parallax ${if (customizationManager.isParallaxEnabled()) "On" else "Off"}")
            append(" • Breathing ${if (customizationManager.isBreathingEnabled()) "On" else "Off"}")
            append(" • Color Shift ${if (customizationManager.isColorShiftEnabled()) "On" else "Off"}")
        }
    }
}
