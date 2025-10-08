package com.stash.opusplayer.ui.preferences

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.fragment.app.Fragment
import androidx.preference.PreferenceManager
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import com.google.android.material.slider.Slider
import com.google.android.material.switchmaterial.SwitchMaterial
import com.stash.opusplayer.R

/**
 * Fragment for managing animation preferences and performance optimization
 */
class AnimationPreferencesFragment : Fragment() {

    private lateinit var prefs: android.content.SharedPreferences
    
    companion object {
        // Animation preference keys
        const val PREF_ANIMATIONS_ENABLED = "animations_enabled"
        const val PREF_FADE_ANIMATIONS = "fade_animations_enabled"
        const val PREF_SCALE_ANIMATIONS = "scale_animations_enabled"
        const val PREF_SLIDE_ANIMATIONS = "slide_animations_enabled"
        const val PREF_ROTATION_ANIMATIONS = "rotation_animations_enabled"
        const val PREF_BOUNCE_ANIMATIONS = "bounce_animations_enabled"
        const val PREF_ELASTIC_ANIMATIONS = "elastic_animations_enabled"
        const val PREF_PULSE_ANIMATIONS = "pulse_animations_enabled"
        const val PREF_RIPPLE_ANIMATIONS = "ripple_animations_enabled"
        const val PREF_SHAKE_ANIMATIONS = "shake_animations_enabled"
        
        // Performance preference keys
        const val PREF_PERFORMANCE_MODE = "performance_mode_enabled"
        const val PREF_REDUCE_MOTION = "reduce_motion_enabled"
        const val PREF_BATTERY_SAVER_MODE = "battery_saver_animations"
        const val PREF_HIGH_REFRESH_RATE = "high_refresh_rate_animations"
        
        // Timing preference keys
        const val PREF_ANIMATION_DURATION_MULTIPLIER = "animation_duration_multiplier"
        const val PREF_ANIMATION_INTERPOLATOR = "animation_interpolator"
        
        // Visual effect preference keys
        const val PREF_PARALLAX_EFFECTS = "parallax_effects_enabled"
        const val PREF_PARTICLE_EFFECTS = "particle_effects_enabled"
        const val PREF_BLUR_EFFECTS = "blur_effects_enabled"
        const val PREF_SHADOW_ANIMATIONS = "shadow_animations_enabled"
        const val PREF_COLOR_ANIMATIONS = "color_animations_enabled"
    }
    
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        prefs = PreferenceManager.getDefaultSharedPreferences(requireContext())
        return createAnimationPreferencesView()
    }
    
    private fun createAnimationPreferencesView(): View {
        val scrollView = ScrollView(requireContext())
        val layout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        
        // Title
        val title = TextView(requireContext()).apply {
            text = "Animation & Visual Effects"
            textSize = 24f
            setPadding(0, 0, 0, 32)
            setTextColor(resources.getColor(android.R.color.white, null))
        }
        layout.addView(title)
        
        // Master Controls Section
        addSectionHeader(layout, "Master Controls")
        layout.addView(buildMasterControlsSection())
        
        // Individual Animations Section
        addSectionHeader(layout, "Individual Animations")
        layout.addView(buildIndividualAnimationsSection())
        
        // Performance Section
        addSectionHeader(layout, "Performance & Optimization")
        layout.addView(buildPerformanceSection())
        
        // Timing Controls Section
        addSectionHeader(layout, "Timing & Motion")
        layout.addView(buildTimingSection())
        
        // Visual Effects Section
        addSectionHeader(layout, "Visual Effects")
        layout.addView(buildVisualEffectsSection())
        
        // Preset Profiles Section
        addSectionHeader(layout, "Animation Profiles")
        layout.addView(buildPresetsSection())
        
        scrollView.addView(layout)
        return scrollView
    }
    
    private fun buildMasterControlsSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Master animation toggle
        val masterToggle = SwitchMaterial(requireContext()).apply {
            text = "Enable All Animations"
            isChecked = prefs.getBoolean(PREF_ANIMATIONS_ENABLED, true)
            setOnCheckedChangeListener { _, isChecked ->
                prefs.edit().putBoolean(PREF_ANIMATIONS_ENABLED, isChecked).apply()
                updateChildAnimationStates(isChecked)
                showToast("Animation system ${if (isChecked) "enabled" else "disabled"}")
            }
        }
        section.addView(masterToggle)
        
        // Reduce motion (accessibility)
        val reduceMotionToggle = SwitchMaterial(requireContext()).apply {
            text = "Reduce Motion (Accessibility)"
            isChecked = prefs.getBoolean(PREF_REDUCE_MOTION, false)
            setOnCheckedChangeListener { _, isChecked ->
                prefs.edit().putBoolean(PREF_REDUCE_MOTION, isChecked).apply()
                if (isChecked) {
                    applyReducedMotionProfile()
                }
                showToast("Reduced motion ${if (isChecked) "enabled" else "disabled"}")
            }
        }
        section.addView(reduceMotionToggle)
        
        return section
    }
    
    private fun buildIndividualAnimationsSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        val animationTypes = listOf(
            "Fade Animations" to PREF_FADE_ANIMATIONS,
            "Scale Animations" to PREF_SCALE_ANIMATIONS,
            "Slide Animations" to PREF_SLIDE_ANIMATIONS,
            "Rotation Animations" to PREF_ROTATION_ANIMATIONS,
            "Bounce Animations" to PREF_BOUNCE_ANIMATIONS,
            "Elastic Animations" to PREF_ELASTIC_ANIMATIONS,
            "Pulse Animations" to PREF_PULSE_ANIMATIONS,
            "Ripple Animations" to PREF_RIPPLE_ANIMATIONS,
            "Shake Animations" to PREF_SHAKE_ANIMATIONS
        )
        
        animationTypes.forEach { (name, key) ->
            val toggle = SwitchMaterial(requireContext()).apply {
                text = name
                isChecked = prefs.getBoolean(key, true)
                setOnCheckedChangeListener { _, isChecked ->
                    prefs.edit().putBoolean(key, isChecked).apply()
                    showToast("$name ${if (isChecked) "enabled" else "disabled"}")
                }
            }
            section.addView(toggle)
        }
        
        return section
    }
    
    private fun buildPerformanceSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Performance mode toggle
        val performanceModeToggle = SwitchMaterial(requireContext()).apply {
            text = "Performance Mode (Reduce Animation Quality)"
            isChecked = prefs.getBoolean(PREF_PERFORMANCE_MODE, false)
            setOnCheckedChangeListener { _, isChecked ->
                prefs.edit().putBoolean(PREF_PERFORMANCE_MODE, isChecked).apply()
                if (isChecked) {
                    applyPerformanceProfile()
                }
                showToast("Performance mode ${if (isChecked) "enabled" else "disabled"}")
            }
        }
        section.addView(performanceModeToggle)
        
        // Battery saver mode
        val batterySaverToggle = SwitchMaterial(requireContext()).apply {
            text = "Battery Saver Mode"
            isChecked = prefs.getBoolean(PREF_BATTERY_SAVER_MODE, false)
            setOnCheckedChangeListener { _, isChecked ->
                prefs.edit().putBoolean(PREF_BATTERY_SAVER_MODE, isChecked).apply()
                if (isChecked) {
                    applyBatterySaverProfile()
                }
                showToast("Battery saver ${if (isChecked) "enabled" else "disabled"}")
            }
        }
        section.addView(batterySaverToggle)
        
        // High refresh rate support
        val highRefreshToggle = SwitchMaterial(requireContext()).apply {
            text = "High Refresh Rate Animations (120Hz/90Hz)"
            isChecked = prefs.getBoolean(PREF_HIGH_REFRESH_RATE, true)
            setOnCheckedChangeListener { _, isChecked ->
                prefs.edit().putBoolean(PREF_HIGH_REFRESH_RATE, isChecked).apply()
                showToast("High refresh rate ${if (isChecked) "enabled" else "disabled"}")
            }
        }
        section.addView(highRefreshToggle)
        
        return section
    }
    
    private fun buildTimingSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        // Duration multiplier slider
        val durationLabel = TextView(requireContext()).apply {
            text = "Animation Speed"
            textSize = 16f
            setPadding(0, 16, 0, 8)
        }
        section.addView(durationLabel)
        
        val durationSlider = Slider(requireContext()).apply {
            valueFrom = 0.25f
            valueTo = 2.0f
            stepSize = 0.25f
            value = prefs.getFloat(PREF_ANIMATION_DURATION_MULTIPLIER, 1.0f)
            
            addOnChangeListener { _, value, _ ->
                prefs.edit().putFloat(PREF_ANIMATION_DURATION_MULTIPLIER, value).apply()
                val speedText = when {
                    value < 0.75f -> "Very Fast"
                    value < 1.0f -> "Fast"
                    value == 1.0f -> "Normal"
                    value <= 1.5f -> "Slow"
                    else -> "Very Slow"
                }
                durationLabel.text = "Animation Speed: $speedText"
            }
        }
        section.addView(durationSlider)
        
        // Interpolator selection
        val interpolatorLabel = TextView(requireContext()).apply {
            text = "Animation Style"
            textSize = 16f
            setPadding(0, 16, 0, 8)
        }
        section.addView(interpolatorLabel)
        
        val interpolatorSpinner = Spinner(requireContext()).apply {
            val interpolators = arrayOf(
                "Linear", "Accelerate", "Decelerate", "AccelerateDecelerate", 
                "Bounce", "Overshoot", "Anticipate", "Elastic"
            )
            adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, interpolators).apply {
                setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            }
            setSelection(prefs.getString(PREF_ANIMATION_INTERPOLATOR, "AccelerateDecelerate")?.let { 
                interpolators.indexOf(it).coerceAtLeast(0) 
            } ?: 3)
            
            onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    val selectedInterpolator = interpolators[position]
                    prefs.edit().putString(PREF_ANIMATION_INTERPOLATOR, selectedInterpolator).apply()
                    showToast("Animation style: $selectedInterpolator")
                }
                override fun onNothingSelected(parent: AdapterView<*>?) {}
            }
        }
        section.addView(interpolatorSpinner)
        
        return section
    }
    
    private fun buildVisualEffectsSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        val visualEffects = listOf(
            "Parallax Effects" to PREF_PARALLAX_EFFECTS,
            "Particle Effects" to PREF_PARTICLE_EFFECTS,
            "Blur Effects" to PREF_BLUR_EFFECTS,
            "Shadow Animations" to PREF_SHADOW_ANIMATIONS,
            "Color Animations" to PREF_COLOR_ANIMATIONS
        )
        
        visualEffects.forEach { (name, key) ->
            val toggle = SwitchMaterial(requireContext()).apply {
                text = name
                isChecked = prefs.getBoolean(key, true)
                setOnCheckedChangeListener { _, isChecked ->
                    prefs.edit().putBoolean(key, isChecked).apply()
                    showToast("$name ${if (isChecked) "enabled" else "disabled"}")
                }
            }
            section.addView(toggle)
        }
        
        return section
    }
    
    private fun buildPresetsSection(): View {
        val section = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
        }
        
        val chipGroup = ChipGroup(requireContext())
        
        val presets = listOf(
            "Minimal" to ::applyMinimalProfile,
            "Standard" to ::applyStandardProfile,
            "Rich" to ::applyRichProfile,
            "Gaming" to ::applyGamingProfile,
            "Accessibility" to ::applyAccessibilityProfile
        )
        
        presets.forEach { (name, action) ->
            val chip = Chip(requireContext()).apply {
                text = name
                isCheckable = false
                setOnClickListener {
                    action.invoke()
                    showToast("Applied $name animation profile")
                }
            }
            chipGroup.addView(chip)
        }
        
        section.addView(chipGroup)
        return section
    }
    
    private fun addSectionHeader(parent: LinearLayout, title: String) {
        val header = TextView(requireContext()).apply {
            text = title
            textSize = 18f
            setPadding(0, 24, 0, 12)
            setTextColor(resources.getColor(android.R.color.holo_blue_bright, null))
        }
        parent.addView(header)
    }
    
    private fun updateChildAnimationStates(enabled: Boolean) {
        if (!enabled) {
            // Disable all individual animations when master is disabled
            val keys = listOf(
                PREF_FADE_ANIMATIONS, PREF_SCALE_ANIMATIONS, PREF_SLIDE_ANIMATIONS,
                PREF_ROTATION_ANIMATIONS, PREF_BOUNCE_ANIMATIONS, PREF_ELASTIC_ANIMATIONS,
                PREF_PULSE_ANIMATIONS, PREF_RIPPLE_ANIMATIONS, PREF_SHAKE_ANIMATIONS
            )
            
            val editor = prefs.edit()
            keys.forEach { key -> editor.putBoolean(key, false) }
            editor.apply()
        }
    }
    
    private fun applyReducedMotionProfile() {
        prefs.edit().apply {
            putBoolean(PREF_BOUNCE_ANIMATIONS, false)
            putBoolean(PREF_ELASTIC_ANIMATIONS, false)
            putBoolean(PREF_SHAKE_ANIMATIONS, false)
            putBoolean(PREF_ROTATION_ANIMATIONS, false)
            putBoolean(PREF_PARALLAX_EFFECTS, false)
            putFloat(PREF_ANIMATION_DURATION_MULTIPLIER, 0.5f)
            putString(PREF_ANIMATION_INTERPOLATOR, "Linear")
            apply()
        }
    }
    
    private fun applyPerformanceProfile() {
        prefs.edit().apply {
            putBoolean(PREF_PARTICLE_EFFECTS, false)
            putBoolean(PREF_BLUR_EFFECTS, false)
            putBoolean(PREF_SHADOW_ANIMATIONS, false)
            putBoolean(PREF_COLOR_ANIMATIONS, false)
            putFloat(PREF_ANIMATION_DURATION_MULTIPLIER, 0.75f)
            apply()
        }
    }
    
    private fun applyBatterySaverProfile() {
        prefs.edit().apply {
            putBoolean(PREF_PARTICLE_EFFECTS, false)
            putBoolean(PREF_BLUR_EFFECTS, false)
            putBoolean(PREF_PARALLAX_EFFECTS, false)
            putBoolean(PREF_HIGH_REFRESH_RATE, false)
            putFloat(PREF_ANIMATION_DURATION_MULTIPLIER, 0.5f)
            apply()
        }
    }
    
    private fun applyMinimalProfile() {
        val editor = prefs.edit()
        listOf(
            PREF_FADE_ANIMATIONS to true,
            PREF_SCALE_ANIMATIONS to false,
            PREF_SLIDE_ANIMATIONS to true,
            PREF_ROTATION_ANIMATIONS to false,
            PREF_BOUNCE_ANIMATIONS to false,
            PREF_ELASTIC_ANIMATIONS to false,
            PREF_PULSE_ANIMATIONS to false,
            PREF_RIPPLE_ANIMATIONS to false,
            PREF_SHAKE_ANIMATIONS to false,
            PREF_PARALLAX_EFFECTS to false,
            PREF_PARTICLE_EFFECTS to false
        ).forEach { (key, value) -> editor.putBoolean(key, value) }
        editor.putFloat(PREF_ANIMATION_DURATION_MULTIPLIER, 0.75f)
        editor.apply()
    }
    
    private fun applyStandardProfile() {
        val editor = prefs.edit()
        listOf(
            PREF_FADE_ANIMATIONS to true,
            PREF_SCALE_ANIMATIONS to true,
            PREF_SLIDE_ANIMATIONS to true,
            PREF_ROTATION_ANIMATIONS to false,
            PREF_BOUNCE_ANIMATIONS to false,
            PREF_ELASTIC_ANIMATIONS to false,
            PREF_PULSE_ANIMATIONS to true,
            PREF_RIPPLE_ANIMATIONS to true,
            PREF_SHAKE_ANIMATIONS to false,
            PREF_PARALLAX_EFFECTS to false,
            PREF_PARTICLE_EFFECTS to false
        ).forEach { (key, value) -> editor.putBoolean(key, value) }
        editor.putFloat(PREF_ANIMATION_DURATION_MULTIPLIER, 1.0f)
        editor.apply()
    }
    
    private fun applyRichProfile() {
        val editor = prefs.edit()
        listOf(
            PREF_FADE_ANIMATIONS to true,
            PREF_SCALE_ANIMATIONS to true,
            PREF_SLIDE_ANIMATIONS to true,
            PREF_ROTATION_ANIMATIONS to true,
            PREF_BOUNCE_ANIMATIONS to true,
            PREF_ELASTIC_ANIMATIONS to true,
            PREF_PULSE_ANIMATIONS to true,
            PREF_RIPPLE_ANIMATIONS to true,
            PREF_SHAKE_ANIMATIONS to true,
            PREF_PARALLAX_EFFECTS to true,
            PREF_PARTICLE_EFFECTS to true,
            PREF_BLUR_EFFECTS to true,
            PREF_SHADOW_ANIMATIONS to true,
            PREF_COLOR_ANIMATIONS to true
        ).forEach { (key, value) -> editor.putBoolean(key, value) }
        editor.putFloat(PREF_ANIMATION_DURATION_MULTIPLIER, 1.25f)
        editor.apply()
    }
    
    private fun applyGamingProfile() {
        val editor = prefs.edit()
        listOf(
            PREF_FADE_ANIMATIONS to true,
            PREF_SCALE_ANIMATIONS to true,
            PREF_SLIDE_ANIMATIONS to true,
            PREF_ROTATION_ANIMATIONS to false,
            PREF_BOUNCE_ANIMATIONS to false,
            PREF_ELASTIC_ANIMATIONS to false,
            PREF_PULSE_ANIMATIONS to true,
            PREF_RIPPLE_ANIMATIONS to true,
            PREF_SHAKE_ANIMATIONS to false,
            PREF_HIGH_REFRESH_RATE to true,
            PREF_PERFORMANCE_MODE to false
        ).forEach { (key, value) -> editor.putBoolean(key, value) }
        editor.putFloat(PREF_ANIMATION_DURATION_MULTIPLIER, 0.5f)
        editor.apply()
    }
    
    private fun applyAccessibilityProfile() {
        applyReducedMotionProfile()
    }
    
    private fun showToast(message: String) {
        Toast.makeText(requireContext(), message, Toast.LENGTH_SHORT).show()
    }
}