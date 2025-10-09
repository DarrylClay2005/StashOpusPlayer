package com.stash.opusplayer.ui.preferences

import android.os.Bundle
import androidx.preference.PreferenceFragmentCompat
import androidx.preference.SwitchPreferenceCompat
import androidx.preference.SeekBarPreference
import androidx.preference.ListPreference
import com.stash.opusplayer.R

/**
 * Fragment for animation settings and preferences
 */
class AnimationSettingsFragment : PreferenceFragmentCompat() {

    override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
        setPreferencesFromResource(R.xml.animation_preferences, rootKey)
        
        setupPreferences()
    }
    
    private fun setupPreferences() {
        // UI Animation toggles
        val uiAnimationsEnabled = findPreference<SwitchPreferenceCompat>("ui_animations_enabled")
        val buttonAnimationsEnabled = findPreference<SwitchPreferenceCompat>("button_animations_enabled")
        val listAnimationsEnabled = findPreference<SwitchPreferenceCompat>("list_animations_enabled")
        val slideAnimationsEnabled = findPreference<SwitchPreferenceCompat>("slide_animations_enabled")
        
        // SynthWave visualizer toggles
        val synthwaveLightning = findPreference<SwitchPreferenceCompat>("synthwave_lightning")
        val synthwaveParticles = findPreference<SwitchPreferenceCompat>("synthwave_particles")
        val synthwaveRipples = findPreference<SwitchPreferenceCompat>("synthwave_ripples")
        val synthwaveBreathing = findPreference<SwitchPreferenceCompat>("synthwave_breathing")
        val synthwaveColorShift = findPreference<SwitchPreferenceCompat>("synthwave_color_shift")
        val synthwaveIntensity = findPreference<SeekBarPreference>("synthwave_intensity")
        
        // Player animation toggles
        val playerPulseEnabled = findPreference<SwitchPreferenceCompat>("player_pulse_enabled")
        val playerBounceEnabled = findPreference<SwitchPreferenceCompat>("player_bounce_enabled")
        val albumArtRotation = findPreference<SwitchPreferenceCompat>("album_art_rotation")
        val progressWaveEnabled = findPreference<SwitchPreferenceCompat>("progress_wave_enabled")
        
        // Feedback animation toggles
        val hapticFeedbackEnabled = findPreference<SwitchPreferenceCompat>("haptic_feedback_enabled")
        val visualFeedbackEnabled = findPreference<SwitchPreferenceCompat>("visual_feedback_enabled")
        val rippleFeedbackEnabled = findPreference<SwitchPreferenceCompat>("ripple_feedback_enabled")
        
        // Performance settings
        val performanceMode = findPreference<ListPreference>("animation_performance_mode")
        val reduceAnimationsBattery = findPreference<SwitchPreferenceCompat>("reduce_animations_battery")
        
        // Set up listeners for important settings
        uiAnimationsEnabled?.setOnPreferenceChangeListener { _, newValue ->
            val enabled = newValue as Boolean
            // Update dependent animations
            buttonAnimationsEnabled?.isEnabled = enabled
            listAnimationsEnabled?.isEnabled = enabled
            slideAnimationsEnabled?.isEnabled = enabled
            true
        }
        
        // Set up SynthWave intensity listener
        synthwaveIntensity?.setOnPreferenceChangeListener { _, newValue ->
            val intensity = (newValue as Int) / 100f
            // Update intensity in shared preferences for visualizer
            preferenceManager.sharedPreferences?.edit()
                ?.putFloat("synthwave_intensity", intensity)
                ?.apply()
            true
        }
        
        // Set up performance mode listener
        performanceMode?.setOnPreferenceChangeListener { _, newValue ->
            when (newValue as String) {
                "high_performance" -> {
                    // Enable all animations for best visual experience
                    enableAllAnimations(true)
                }
                "balanced" -> {
                    // Enable most animations but reduce intensity
                    enableBalancedAnimations()
                }
                "battery_saver" -> {
                    // Disable non-essential animations
                    enableBatterySaverAnimations()
                }
            }
            true
        }
        
        // Set up battery saver mode listener
        reduceAnimationsBattery?.setOnPreferenceChangeListener { _, newValue ->
            val batterySaver = newValue as Boolean
            if (batterySaver) {
                enableBatterySaverAnimations()
            } else {
                enableBalancedAnimations()
            }
            true
        }
        
        // Initialize dependent preferences state
        val currentUiAnimationsEnabled = uiAnimationsEnabled?.isChecked ?: true
        buttonAnimationsEnabled?.isEnabled = currentUiAnimationsEnabled
        listAnimationsEnabled?.isEnabled = currentUiAnimationsEnabled
        slideAnimationsEnabled?.isEnabled = currentUiAnimationsEnabled
    }
    
    private fun enableAllAnimations(enable: Boolean) {
        val prefs = preferenceManager.sharedPreferences
        prefs?.edit()?.apply {
            putBoolean("ui_animations_enabled", enable)
            putBoolean("button_animations_enabled", enable)
            putBoolean("list_animations_enabled", enable)
            putBoolean("slide_animations_enabled", enable)
            putBoolean("synthwave_lightning", enable)
            putBoolean("synthwave_particles", enable)
            putBoolean("synthwave_ripples", enable)
            putBoolean("synthwave_breathing", enable)
            putBoolean("synthwave_color_shift", enable)
            putBoolean("player_pulse_enabled", enable)
            putBoolean("player_bounce_enabled", enable)
            putBoolean("progress_wave_enabled", enable)
            putBoolean("visual_feedback_enabled", enable)
            putBoolean("ripple_feedback_enabled", enable)
            putFloat("synthwave_intensity", if (enable) 1.0f else 0.5f)
        }?.apply()
        
        // Update UI
        refreshPreferences()
    }
    
    private fun enableBalancedAnimations() {
        val prefs = preferenceManager.sharedPreferences
        prefs?.edit()?.apply {
            putBoolean("ui_animations_enabled", true)
            putBoolean("button_animations_enabled", true)
            putBoolean("list_animations_enabled", true)
            putBoolean("slide_animations_enabled", true)
            putBoolean("synthwave_lightning", true)
            putBoolean("synthwave_particles", true)
            putBoolean("synthwave_ripples", true)
            putBoolean("synthwave_breathing", false)
            putBoolean("synthwave_color_shift", true)
            putBoolean("player_pulse_enabled", true)
            putBoolean("player_bounce_enabled", false)
            putBoolean("album_art_rotation", false)
            putBoolean("progress_wave_enabled", true)
            putBoolean("visual_feedback_enabled", true)
            putBoolean("ripple_feedback_enabled", false)
            putFloat("synthwave_intensity", 0.7f)
        }?.apply()
        
        // Update UI
        refreshPreferences()
    }
    
    private fun enableBatterySaverAnimations() {
        val prefs = preferenceManager.sharedPreferences
        prefs?.edit()?.apply {
            putBoolean("ui_animations_enabled", true)
            putBoolean("button_animations_enabled", false)
            putBoolean("list_animations_enabled", false)
            putBoolean("slide_animations_enabled", true)
            putBoolean("synthwave_lightning", false)
            putBoolean("synthwave_particles", false)
            putBoolean("synthwave_ripples", false)
            putBoolean("synthwave_breathing", false)
            putBoolean("synthwave_color_shift", false)
            putBoolean("player_pulse_enabled", false)
            putBoolean("player_bounce_enabled", false)
            putBoolean("album_art_rotation", false)
            putBoolean("progress_wave_enabled", false)
            putBoolean("visual_feedback_enabled", true)
            putBoolean("ripple_feedback_enabled", false)
            putFloat("synthwave_intensity", 0.3f)
        }?.apply()
        
        // Update UI
        refreshPreferences()
    }
    
    private fun refreshPreferences() {
        // Refresh all preference values from SharedPreferences
        preferenceScreen?.let { screen ->
            for (i in 0 until screen.preferenceCount) {
                val preference = screen.getPreference(i)
                if (preference is SwitchPreferenceCompat) {
                    preference.isChecked = preferenceManager.sharedPreferences
                        ?.getBoolean(preference.key, preference.isChecked) ?: preference.isChecked
                } else if (preference is SeekBarPreference) {
                    if (preference.key == "synthwave_intensity") {
                        val intensity = preferenceManager.sharedPreferences
                            ?.getFloat("synthwave_intensity", 0.5f) ?: 0.5f
                        preference.value = (intensity * 100).toInt()
                    }
                }
            }
        }
    }
}