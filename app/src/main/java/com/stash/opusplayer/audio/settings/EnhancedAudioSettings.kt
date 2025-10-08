package com.stash.opusplayer.audio.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.preference.PreferenceManager
import com.stash.opusplayer.audio.EnhancedAudioManager

/**
 * Manages persistence of enhanced audio settings
 */
class EnhancedAudioSettings(private val context: Context) {
    
    // Cloud sync will be implemented later
    
    companion object {
        // Professional Audio Processor Settings
        private const val PREF_PROFESSIONAL_PROCESSOR_ENABLED = "professional_processor_enabled"
        private const val PREF_COMPRESSION_ENABLED = "compression_enabled"
        private const val PREF_COMPRESSION_THRESHOLD = "compression_threshold"
        private const val PREF_COMPRESSION_RATIO = "compression_ratio"
        private const val PREF_COMPRESSION_ATTACK = "compression_attack"
        private const val PREF_COMPRESSION_RELEASE = "compression_release"
        private const val PREF_STEREO_WIDTH = "stereo_width"
        private const val PREF_AUTO_GAIN_ENABLED = "auto_gain_enabled"
        private const val PREF_TARGET_LUFS = "target_lufs"
        private const val PREF_CROSSFEED_ENABLED = "crossfeed_enabled"
        private const val PREF_TUBE_WARMTH = "tube_warmth"
        private const val PREF_CURRENT_AUDIO_PROFILE = "current_audio_profile"
        
        // Spectrum Analyzer Settings
        private const val PREF_SPECTRUM_ANALYZER_ENABLED = "spectrum_analyzer_enabled"
        private const val PREF_SPECTRUM_SENSITIVITY = "spectrum_sensitivity"
        private const val PREF_SPECTRUM_SMOOTHING = "spectrum_smoothing"
        
        // Enhanced Equalizer Settings
        private const val PREF_ENHANCED_EQ_ENABLED = "enhanced_eq_enabled"
        private const val PREF_ENHANCED_EQ_PRESET = "enhanced_eq_preset"
        private const val PREF_ENHANCED_BAND_LEVELS = "enhanced_band_levels"
        
        // Default Values
        private const val DEFAULT_COMPRESSION_THRESHOLD = -12f
        private const val DEFAULT_COMPRESSION_RATIO = 4f
        private const val DEFAULT_COMPRESSION_ATTACK = 5f
        private const val DEFAULT_COMPRESSION_RELEASE = 50f
        private const val DEFAULT_STEREO_WIDTH = 1f
        private const val DEFAULT_TARGET_LUFS = -16f
        private const val DEFAULT_TUBE_WARMTH = 0f
        private const val DEFAULT_SPECTRUM_SENSITIVITY = 1f
        private const val DEFAULT_SPECTRUM_SMOOTHING = 0.8f
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    /**
     * Professional Audio Processor Settings
     */
    
    fun isProfessionalProcessorEnabled(): Boolean {
        return prefs.getBoolean(PREF_PROFESSIONAL_PROCESSOR_ENABLED, false)
    }
    
    fun setProfessionalProcessorEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_PROFESSIONAL_PROCESSOR_ENABLED, enabled).apply()
    }
    
    fun isCompressionEnabled(): Boolean {
        return prefs.getBoolean(PREF_COMPRESSION_ENABLED, false)
    }
    
    fun setCompressionEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_COMPRESSION_ENABLED, enabled).apply()
    }
    
    fun getCompressionThreshold(): Float {
        return prefs.getFloat(PREF_COMPRESSION_THRESHOLD, DEFAULT_COMPRESSION_THRESHOLD)
    }
    
    fun setCompressionThreshold(threshold: Float) {
        prefs.edit().putFloat(PREF_COMPRESSION_THRESHOLD, threshold).apply()
    }
    
    fun getCompressionRatio(): Float {
        return prefs.getFloat(PREF_COMPRESSION_RATIO, DEFAULT_COMPRESSION_RATIO)
    }
    
    fun setCompressionRatio(ratio: Float) {
        prefs.edit().putFloat(PREF_COMPRESSION_RATIO, ratio).apply()
    }
    
    fun getCompressionAttack(): Float {
        return prefs.getFloat(PREF_COMPRESSION_ATTACK, DEFAULT_COMPRESSION_ATTACK)
    }
    
    fun setCompressionAttack(attack: Float) {
        prefs.edit().putFloat(PREF_COMPRESSION_ATTACK, attack).apply()
    }
    
    fun getCompressionRelease(): Float {
        return prefs.getFloat(PREF_COMPRESSION_RELEASE, DEFAULT_COMPRESSION_RELEASE)
    }
    
    fun setCompressionRelease(release: Float) {
        prefs.edit().putFloat(PREF_COMPRESSION_RELEASE, release).apply()
    }
    
    fun getStereoWidth(): Float {
        return prefs.getFloat(PREF_STEREO_WIDTH, DEFAULT_STEREO_WIDTH)
    }
    
    fun setStereoWidth(width: Float) {
        prefs.edit().putFloat(PREF_STEREO_WIDTH, width).apply()
    }
    
    fun isAutoGainEnabled(): Boolean {
        return prefs.getBoolean(PREF_AUTO_GAIN_ENABLED, false)
    }
    
    fun setAutoGainEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_AUTO_GAIN_ENABLED, enabled).apply()
    }
    
    fun getTargetLufs(): Float {
        return prefs.getFloat(PREF_TARGET_LUFS, DEFAULT_TARGET_LUFS)
    }
    
    fun setTargetLufs(lufs: Float) {
        prefs.edit().putFloat(PREF_TARGET_LUFS, lufs).apply()
    }
    
    fun isCrossfeedEnabled(): Boolean {
        return prefs.getBoolean(PREF_CROSSFEED_ENABLED, false)
    }
    
    fun setCrossfeedEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_CROSSFEED_ENABLED, enabled).apply()
    }
    
    fun getTubeWarmth(): Float {
        return prefs.getFloat(PREF_TUBE_WARMTH, DEFAULT_TUBE_WARMTH)
    }
    
    fun setTubeWarmth(warmth: Float) {
        prefs.edit().putFloat(PREF_TUBE_WARMTH, warmth).apply()
    }
    
    fun getCurrentAudioProfile(): String {
        return prefs.getString(PREF_CURRENT_AUDIO_PROFILE, "BALANCED") ?: "BALANCED"
    }
    
    fun setCurrentAudioProfile(profile: String) {
        prefs.edit().putString(PREF_CURRENT_AUDIO_PROFILE, profile).apply()
    }
    
    /**
     * Spectrum Analyzer Settings
     */
    
    fun isSpectrumAnalyzerEnabled(): Boolean {
        return prefs.getBoolean(PREF_SPECTRUM_ANALYZER_ENABLED, true)
    }
    
    fun setSpectrumAnalyzerEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_SPECTRUM_ANALYZER_ENABLED, enabled).apply()
    }
    
    fun getSpectrumSensitivity(): Float {
        return prefs.getFloat(PREF_SPECTRUM_SENSITIVITY, DEFAULT_SPECTRUM_SENSITIVITY)
    }
    
    fun setSpectrumSensitivity(sensitivity: Float) {
        prefs.edit().putFloat(PREF_SPECTRUM_SENSITIVITY, sensitivity).apply()
    }
    
    fun getSpectrumSmoothing(): Float {
        return prefs.getFloat(PREF_SPECTRUM_SMOOTHING, DEFAULT_SPECTRUM_SMOOTHING)
    }
    
    fun setSpectrumSmoothing(smoothing: Float) {
        prefs.edit().putFloat(PREF_SPECTRUM_SMOOTHING, smoothing).apply()
    }
    
    /**
     * Enhanced Equalizer Settings
     */
    
    fun isEnhancedEqualizerEnabled(): Boolean {
        return prefs.getBoolean(PREF_ENHANCED_EQ_ENABLED, false)
    }
    
    fun setEnhancedEqualizerEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_ENHANCED_EQ_ENABLED, enabled).apply()
    }
    
    fun getEnhancedEqualizerPreset(): String {
        return prefs.getString(PREF_ENHANCED_EQ_PRESET, "NORMAL") ?: "NORMAL"
    }
    
    fun setEnhancedEqualizerPreset(preset: String) {
        prefs.edit().putString(PREF_ENHANCED_EQ_PRESET, preset).apply()
    }
    
    fun getEnhancedBandLevels(): String {
        return prefs.getString(PREF_ENHANCED_BAND_LEVELS, "") ?: ""
    }
    
    fun setEnhancedBandLevels(bandLevels: String) {
        prefs.edit().putString(PREF_ENHANCED_BAND_LEVELS, bandLevels).apply()
    }
    
    /**
     * Save a complete settings snapshot
     */
    fun saveSettingsSnapshot(): Map<String, Any> {
        val snapshot = mutableMapOf<String, Any>()
        
        // Professional Processor
        snapshot[PREF_PROFESSIONAL_PROCESSOR_ENABLED] = isProfessionalProcessorEnabled()
        snapshot[PREF_COMPRESSION_ENABLED] = isCompressionEnabled()
        snapshot[PREF_COMPRESSION_THRESHOLD] = getCompressionThreshold()
        snapshot[PREF_COMPRESSION_RATIO] = getCompressionRatio()
        snapshot[PREF_COMPRESSION_ATTACK] = getCompressionAttack()
        snapshot[PREF_COMPRESSION_RELEASE] = getCompressionRelease()
        snapshot[PREF_STEREO_WIDTH] = getStereoWidth()
        snapshot[PREF_AUTO_GAIN_ENABLED] = isAutoGainEnabled()
        snapshot[PREF_TARGET_LUFS] = getTargetLufs()
        snapshot[PREF_CROSSFEED_ENABLED] = isCrossfeedEnabled()
        snapshot[PREF_TUBE_WARMTH] = getTubeWarmth()
        snapshot[PREF_CURRENT_AUDIO_PROFILE] = getCurrentAudioProfile()
        
        // Spectrum Analyzer
        snapshot[PREF_SPECTRUM_ANALYZER_ENABLED] = isSpectrumAnalyzerEnabled()
        snapshot[PREF_SPECTRUM_SENSITIVITY] = getSpectrumSensitivity()
        snapshot[PREF_SPECTRUM_SMOOTHING] = getSpectrumSmoothing()
        
        // Enhanced Equalizer
        snapshot[PREF_ENHANCED_EQ_ENABLED] = isEnhancedEqualizerEnabled()
        snapshot[PREF_ENHANCED_EQ_PRESET] = getEnhancedEqualizerPreset()
        snapshot[PREF_ENHANCED_BAND_LEVELS] = getEnhancedBandLevels()
        
        return snapshot
    }
    
    /**
     * Load settings snapshot and apply all
     */
    fun loadSettingsSnapshot(snapshot: Map<String, Any>) {
        val editor = prefs.edit()
        
        snapshot.forEach { (key, value) ->
            when (value) {
                is Boolean -> editor.putBoolean(key, value)
                is Float -> editor.putFloat(key, value)
                is String -> editor.putString(key, value)
                is Int -> editor.putInt(key, value)
                is Long -> editor.putLong(key, value)
            }
        }
        
        editor.apply()
    }
    
    /**
     * Reset all enhanced audio settings to defaults
     */
    fun resetToDefaults() {
        prefs.edit()
            .putBoolean(PREF_PROFESSIONAL_PROCESSOR_ENABLED, false)
            .putBoolean(PREF_COMPRESSION_ENABLED, false)
            .putFloat(PREF_COMPRESSION_THRESHOLD, DEFAULT_COMPRESSION_THRESHOLD)
            .putFloat(PREF_COMPRESSION_RATIO, DEFAULT_COMPRESSION_RATIO)
            .putFloat(PREF_COMPRESSION_ATTACK, DEFAULT_COMPRESSION_ATTACK)
            .putFloat(PREF_COMPRESSION_RELEASE, DEFAULT_COMPRESSION_RELEASE)
            .putFloat(PREF_STEREO_WIDTH, DEFAULT_STEREO_WIDTH)
            .putBoolean(PREF_AUTO_GAIN_ENABLED, false)
            .putFloat(PREF_TARGET_LUFS, DEFAULT_TARGET_LUFS)
            .putBoolean(PREF_CROSSFEED_ENABLED, false)
            .putFloat(PREF_TUBE_WARMTH, DEFAULT_TUBE_WARMTH)
            .putString(PREF_CURRENT_AUDIO_PROFILE, "BALANCED")
            .putBoolean(PREF_SPECTRUM_ANALYZER_ENABLED, true)
            .putFloat(PREF_SPECTRUM_SENSITIVITY, DEFAULT_SPECTRUM_SENSITIVITY)
            .putFloat(PREF_SPECTRUM_SMOOTHING, DEFAULT_SPECTRUM_SMOOTHING)
            .putBoolean(PREF_ENHANCED_EQ_ENABLED, false)
            .putString(PREF_ENHANCED_EQ_PRESET, "NORMAL")
            .putString(PREF_ENHANCED_BAND_LEVELS, "")
            .apply()
            
        // Trigger cloud sync for default reset
        triggerCloudSync()
    }
    
    /**
     * Trigger cloud synchronization of current settings
     */
    private fun triggerCloudSync() {
        try {
            // Cloud sync will be implemented later - for now just log
            android.util.Log.d("EnhancedAudioSettings", "Cloud sync triggered (not yet implemented)")
        } catch (e: Exception) {
            // Cloud sync is optional, don't crash if it fails
            android.util.Log.d("EnhancedAudioSettings", "Cloud sync failed: ${e.message}")
        }
    }
    
    /**
     * Cloud sync methods - to be implemented later
     */
    fun enableCloudSync(): Boolean = false
    fun disableCloudSync(): Boolean = false
    fun isCloudSyncEnabled(): Boolean = false
    fun getCloudSyncInfo(): Map<String, Any> = emptyMap()
    
    /**
     * Override setter methods to include cloud sync trigger
     */
    
    // Override existing setters to add cloud sync
    fun setProfessionalProcessorEnabledWithSync(enabled: Boolean) {
        setProfessionalProcessorEnabled(enabled)
        triggerCloudSync()
    }
    
    fun setCompressionEnabledWithSync(enabled: Boolean) {
        setCompressionEnabled(enabled)
        triggerCloudSync()
    }
    
    fun setCompressionThresholdWithSync(threshold: Float) {
        setCompressionThreshold(threshold)
        triggerCloudSync()
    }
    
    fun setCompressionRatioWithSync(ratio: Float) {
        setCompressionRatio(ratio)
        triggerCloudSync()
    }
    
    fun setStereoWidthWithSync(width: Float) {
        setStereoWidth(width)
        triggerCloudSync()
    }
    
    fun setCurrentAudioProfileWithSync(profile: String) {
        setCurrentAudioProfile(profile)
        triggerCloudSync()
    }
}
