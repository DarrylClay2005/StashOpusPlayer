package com.stash.opusplayer.ui.appearance

import android.content.Context
import android.content.SharedPreferences
import androidx.preference.PreferenceManager
import com.stash.opusplayer.utils.PrefsKeys
import org.json.JSONArray
import org.json.JSONObject

data class AppearancePreferences(
    // Colors
    val primaryColor: Int = 0xFF4A5568.toInt(),
    val accentColor: Int = 0xFFEC407A.toInt(),
    val backgroundColor: Int = 0xFF2D3748.toInt(),
    val textPrimaryColor: Int = 0xFFF7FAFC.toInt(),
    val textSecondaryColor: Int = 0xFFCBD5E0.toInt(),
    
    // Typography
    val fontScale: Float = 1.0f,
    val titleBold: Boolean = false,
    
    // UI Elements
    val buttonSizeScale: Float = 1.0f,
    val cardCornerRadiusDp: Int = 20,
    val shadowsEnabled: Boolean = true,
    val shadowIntensity: Float = 1.0f,
    
    // Background
    val backgroundImageUri: String = "",
    val backgroundBlurRadius: Int = 0,
    val backgroundDimPercent: Int = 30,
    val useSolidBackgroundColor: Boolean = false,
    
    // Animations
    val animationsEnabled: Boolean = true,
    val animationSpeed: AnimationSpeed = AnimationSpeed.NORMAL,
    
    // Mini Player
    val miniPlayerHeightDp: Int = 72,
    val miniPlayerShowArt: Boolean = true,
    val miniPlayerShowArtist: Boolean = true,
    val miniPlayerCompactMode: Boolean = false,
    val miniPlayerSpinningArt: Boolean = false,
    
    // SynthWave Visualizer
    val synthWaveEnabled: Boolean = true,
    val synthWaveProgressMode: Boolean = true,
    val synthWaveUseCustomColors: Boolean = false,
    val synthWavePrimaryColor: Int = 0xFFEC407A.toInt(),
    val synthWaveSecondaryColor: Int = 0xFF9C27B0.toInt(),
    val synthWaveGlowColor: Int = 0xFF00BCD4.toInt(),
    val synthWaveAnimationIntensity: Float = 1.0f,
    val synthWaveParticleCount: Int = 200,
    val synthWaveFrequencyBands: Int = 64,
    val synthWaveLightningEnabled: Boolean = true,
    val synthWaveRippleEnabled: Boolean = true,
    val synthWaveShakeEnabled: Boolean = true,
    val synthWavePerformanceMode: Boolean = false
) {
    
    enum class AnimationSpeed(val multiplier: Float) {
        SLOW(1.5f),
        NORMAL(1.0f),
        FAST(0.7f)
    }
    
    companion object {
        private const val PREFS_NAME = "appearance_prefs"
        private const val VERSION = 1
        
        /**
         * Load preferences from SharedPreferences
         */
        fun fromPrefs(context: Context): AppearancePreferences {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            
            return AppearancePreferences(
                primaryColor = prefs.getInt(PrefsKeys.APPEARANCE_PRIMARY_COLOR, 0xFF4A5568.toInt()),
                accentColor = prefs.getInt(PrefsKeys.APPEARANCE_ACCENT_COLOR, 0xFFEC407A.toInt()),
                backgroundColor = prefs.getInt(PrefsKeys.APPEARANCE_BACKGROUND_COLOR, 0xFF2D3748.toInt()),
                textPrimaryColor = prefs.getInt(PrefsKeys.APPEARANCE_TEXT_PRIMARY_COLOR, 0xFFF7FAFC.toInt()),
                textSecondaryColor = prefs.getInt(PrefsKeys.APPEARANCE_TEXT_SECONDARY_COLOR, 0xFFCBD5E0.toInt()),
                
                fontScale = prefs.getFloat(PrefsKeys.APPEARANCE_FONT_SCALE, 1.0f).coerceIn(0.85f, 1.3f),
                titleBold = prefs.getBoolean(PrefsKeys.APPEARANCE_TITLE_BOLD, false),
                
                buttonSizeScale = prefs.getFloat(PrefsKeys.APPEARANCE_BUTTON_SIZE_SCALE, 1.0f).coerceIn(0.8f, 1.2f),
                cardCornerRadiusDp = prefs.getInt(PrefsKeys.APPEARANCE_CARD_CORNER_RADIUS_DP, 20).coerceIn(8, 32),
                shadowsEnabled = prefs.getBoolean(PrefsKeys.APPEARANCE_SHADOWS_ENABLED, true),
                shadowIntensity = prefs.getFloat(PrefsKeys.APPEARANCE_SHADOW_INTENSITY, 1.0f).coerceIn(0f, 1f),
                
                backgroundImageUri = prefs.getString(PrefsKeys.APPEARANCE_BACKGROUND_IMAGE_URI, "") ?: "",
                backgroundBlurRadius = prefs.getInt(PrefsKeys.APPEARANCE_BACKGROUND_BLUR_RADIUS, 0).coerceIn(0, 25),
                backgroundDimPercent = prefs.getInt(PrefsKeys.APPEARANCE_BACKGROUND_DIM_PERCENT, 30).coerceIn(0, 100),
                useSolidBackgroundColor = prefs.getBoolean(PrefsKeys.APPEARANCE_BACKGROUND_USE_SOLID_COLOR, false),
                
                animationsEnabled = prefs.getBoolean(PrefsKeys.APPEARANCE_ANIMATIONS_ENABLED, true),
                animationSpeed = AnimationSpeed.valueOf(
                    prefs.getString(PrefsKeys.APPEARANCE_ANIMATION_SPEED, AnimationSpeed.NORMAL.name) ?: AnimationSpeed.NORMAL.name
                ),
                
                miniPlayerHeightDp = prefs.getInt(PrefsKeys.APPEARANCE_MINI_PLAYER_HEIGHT_DP, 72).coerceIn(56, 96),
                miniPlayerShowArt = prefs.getBoolean(PrefsKeys.APPEARANCE_MINI_PLAYER_SHOW_ART, true),
                miniPlayerShowArtist = prefs.getBoolean(PrefsKeys.APPEARANCE_MINI_PLAYER_SHOW_ARTIST, true),
                miniPlayerCompactMode = prefs.getBoolean(PrefsKeys.APPEARANCE_MINI_PLAYER_COMPACT_MODE, false),
                miniPlayerSpinningArt = prefs.getBoolean(PrefsKeys.APPEARANCE_MINI_PLAYER_SPINNING_ART, false),
                
                synthWaveEnabled = prefs.getBoolean("synthwave_enabled", true),
                synthWaveProgressMode = prefs.getBoolean(PrefsKeys.APPEARANCE_SYNTHWAVE_PROGRESS_MODE, true),
                synthWaveUseCustomColors = prefs.getBoolean(PrefsKeys.APPEARANCE_SYNTHWAVE_USE_CUSTOM_COLORS, false),
                synthWavePrimaryColor = prefs.getInt(PrefsKeys.APPEARANCE_SYNTHWAVE_PRIMARY_COLOR, 0xFFEC407A.toInt()),
                synthWaveSecondaryColor = prefs.getInt(PrefsKeys.APPEARANCE_SYNTHWAVE_SECONDARY_COLOR, 0xFF9C27B0.toInt()),
                synthWaveGlowColor = prefs.getInt(PrefsKeys.APPEARANCE_SYNTHWAVE_GLOW_COLOR, 0xFF00BCD4.toInt()),
                synthWaveAnimationIntensity = prefs.getFloat("synthwave_animation_intensity", 1.0f).coerceIn(0.1f, 2.0f),
                synthWaveParticleCount = prefs.getInt("synthwave_particle_count", 200).coerceIn(50, 500),
                synthWaveFrequencyBands = prefs.getInt("synthwave_frequency_bands", 64).coerceIn(16, 128),
                synthWaveLightningEnabled = prefs.getBoolean("synthwave_lightning_enabled", true),
                synthWaveRippleEnabled = prefs.getBoolean("synthwave_ripple_enabled", true),
                synthWaveShakeEnabled = prefs.getBoolean("synthwave_shake_enabled", true),
                synthWavePerformanceMode = prefs.getBoolean("synthwave_performance_mode", false)
            )
        }
        
        /**
         * Load from JSON string
         */
        fun fromJson(jsonString: String): AppearancePreferences {
            val json = JSONObject(jsonString)
            
            return AppearancePreferences(
                primaryColor = json.optInt("primaryColor", 0xFF4A5568.toInt()),
                accentColor = json.optInt("accentColor", 0xFFEC407A.toInt()),
                backgroundColor = json.optInt("backgroundColor", 0xFF2D3748.toInt()),
                textPrimaryColor = json.optInt("textPrimaryColor", 0xFFF7FAFC.toInt()),
                textSecondaryColor = json.optInt("textSecondaryColor", 0xFFCBD5E0.toInt()),
                
                fontScale = json.optDouble("fontScale", 1.0).toFloat().coerceIn(0.85f, 1.3f),
                titleBold = json.optBoolean("titleBold", false),
                
                buttonSizeScale = json.optDouble("buttonSizeScale", 1.0).toFloat().coerceIn(0.8f, 1.2f),
                cardCornerRadiusDp = json.optInt("cardCornerRadiusDp", 20).coerceIn(8, 32),
                shadowsEnabled = json.optBoolean("shadowsEnabled", true),
                shadowIntensity = json.optDouble("shadowIntensity", 1.0).toFloat().coerceIn(0f, 1f),
                
                backgroundImageUri = json.optString("backgroundImageUri", ""),
                backgroundBlurRadius = json.optInt("backgroundBlurRadius", 0).coerceIn(0, 25),
                backgroundDimPercent = json.optInt("backgroundDimPercent", 30).coerceIn(0, 100),
                useSolidBackgroundColor = json.optBoolean("useSolidBackgroundColor", false),
                
                animationsEnabled = json.optBoolean("animationsEnabled", true),
                animationSpeed = try {
                    AnimationSpeed.valueOf(json.optString("animationSpeed", AnimationSpeed.NORMAL.name))
                } catch (e: Exception) {
                    AnimationSpeed.NORMAL
                },
                
                miniPlayerHeightDp = json.optInt("miniPlayerHeightDp", 72).coerceIn(56, 96),
                miniPlayerShowArt = json.optBoolean("miniPlayerShowArt", true),
                miniPlayerShowArtist = json.optBoolean("miniPlayerShowArtist", true),
                miniPlayerCompactMode = json.optBoolean("miniPlayerCompactMode", false),
                miniPlayerSpinningArt = json.optBoolean("miniPlayerSpinningArt", false),
                
                synthWaveEnabled = json.optBoolean("synthWaveEnabled", true),
                synthWaveProgressMode = json.optBoolean("synthWaveProgressMode", true),
                synthWaveUseCustomColors = json.optBoolean("synthWaveUseCustomColors", false),
                synthWavePrimaryColor = json.optInt("synthWavePrimaryColor", 0xFFEC407A.toInt()),
                synthWaveSecondaryColor = json.optInt("synthWaveSecondaryColor", 0xFF9C27B0.toInt()),
                synthWaveGlowColor = json.optInt("synthWaveGlowColor", 0xFF00BCD4.toInt()),
                synthWaveAnimationIntensity = json.optDouble("synthWaveAnimationIntensity", 1.0).toFloat().coerceIn(0.1f, 2.0f),
                synthWaveParticleCount = json.optInt("synthWaveParticleCount", 200).coerceIn(50, 500),
                synthWaveFrequencyBands = json.optInt("synthWaveFrequencyBands", 64).coerceIn(16, 128),
                synthWaveLightningEnabled = json.optBoolean("synthWaveLightningEnabled", true),
                synthWaveRippleEnabled = json.optBoolean("synthWaveRippleEnabled", true),
                synthWaveShakeEnabled = json.optBoolean("synthWaveShakeEnabled", true),
                synthWavePerformanceMode = json.optBoolean("synthWavePerformanceMode", false)
            )
        }
        
        /**
         * Reset all preferences to defaults
         */
        fun resetToDefaults(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().clear().apply()
        }
        
        /**
         * Get recent colors
         */
        fun getRecentColors(context: Context): List<Int> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val jsonString = prefs.getString(PrefsKeys.APPEARANCE_RECENT_COLORS_JSON, null)
            
            if (jsonString.isNullOrEmpty()) return emptyList()
            
            return try {
                val jsonArray = JSONArray(jsonString)
                List(jsonArray.length()) { i -> jsonArray.getInt(i) }
            } catch (e: Exception) {
                emptyList()
            }
        }
        
        /**
         * Persist a recent color
         */
        fun persistRecentColor(context: Context, color: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val existing = getRecentColors(context).toMutableList()
            
            // Remove if already exists
            existing.remove(color)
            
            // Add to front
            existing.add(0, color)
            
            // Keep only last 5
            val trimmed = existing.take(5)
            
            // Save as JSON array
            val jsonArray = JSONArray(trimmed)
            prefs.edit()
                .putString(PrefsKeys.APPEARANCE_RECENT_COLORS_JSON, jsonArray.toString())
                .apply()
        }
    }
    
    /**
     * Save to SharedPreferences
     */
    fun saveToPrefs(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        prefs.edit().apply {
            putInt(PrefsKeys.APPEARANCE_PRIMARY_COLOR, primaryColor)
            putInt(PrefsKeys.APPEARANCE_ACCENT_COLOR, accentColor)
            putInt(PrefsKeys.APPEARANCE_BACKGROUND_COLOR, backgroundColor)
            putInt(PrefsKeys.APPEARANCE_TEXT_PRIMARY_COLOR, textPrimaryColor)
            putInt(PrefsKeys.APPEARANCE_TEXT_SECONDARY_COLOR, textSecondaryColor)
            
            putFloat(PrefsKeys.APPEARANCE_FONT_SCALE, fontScale)
            putBoolean(PrefsKeys.APPEARANCE_TITLE_BOLD, titleBold)
            
            putFloat(PrefsKeys.APPEARANCE_BUTTON_SIZE_SCALE, buttonSizeScale)
            putInt(PrefsKeys.APPEARANCE_CARD_CORNER_RADIUS_DP, cardCornerRadiusDp)
            putBoolean(PrefsKeys.APPEARANCE_SHADOWS_ENABLED, shadowsEnabled)
            putFloat(PrefsKeys.APPEARANCE_SHADOW_INTENSITY, shadowIntensity)
            
            putString(PrefsKeys.APPEARANCE_BACKGROUND_IMAGE_URI, backgroundImageUri)
            putInt(PrefsKeys.APPEARANCE_BACKGROUND_BLUR_RADIUS, backgroundBlurRadius)
            putInt(PrefsKeys.APPEARANCE_BACKGROUND_DIM_PERCENT, backgroundDimPercent)
            putBoolean(PrefsKeys.APPEARANCE_BACKGROUND_USE_SOLID_COLOR, useSolidBackgroundColor)
            
            putBoolean(PrefsKeys.APPEARANCE_ANIMATIONS_ENABLED, animationsEnabled)
            putString(PrefsKeys.APPEARANCE_ANIMATION_SPEED, animationSpeed.name)
            
            putInt(PrefsKeys.APPEARANCE_MINI_PLAYER_HEIGHT_DP, miniPlayerHeightDp)
            putBoolean(PrefsKeys.APPEARANCE_MINI_PLAYER_SHOW_ART, miniPlayerShowArt)
            putBoolean(PrefsKeys.APPEARANCE_MINI_PLAYER_SHOW_ARTIST, miniPlayerShowArtist)
            putBoolean(PrefsKeys.APPEARANCE_MINI_PLAYER_COMPACT_MODE, miniPlayerCompactMode)
            putBoolean(PrefsKeys.APPEARANCE_MINI_PLAYER_SPINNING_ART, miniPlayerSpinningArt)
            
            putBoolean("synthwave_enabled", synthWaveEnabled)
            putBoolean(PrefsKeys.APPEARANCE_SYNTHWAVE_PROGRESS_MODE, synthWaveProgressMode)
            putBoolean(PrefsKeys.APPEARANCE_SYNTHWAVE_USE_CUSTOM_COLORS, synthWaveUseCustomColors)
            putInt(PrefsKeys.APPEARANCE_SYNTHWAVE_PRIMARY_COLOR, synthWavePrimaryColor)
            putInt(PrefsKeys.APPEARANCE_SYNTHWAVE_SECONDARY_COLOR, synthWaveSecondaryColor)
            putInt(PrefsKeys.APPEARANCE_SYNTHWAVE_GLOW_COLOR, synthWaveGlowColor)
            putFloat("synthwave_animation_intensity", synthWaveAnimationIntensity)
            putInt("synthwave_particle_count", synthWaveParticleCount)
            putInt("synthwave_frequency_bands", synthWaveFrequencyBands)
            putBoolean("synthwave_lightning_enabled", synthWaveLightningEnabled)
            putBoolean("synthwave_ripple_enabled", synthWaveRippleEnabled)
            putBoolean("synthwave_shake_enabled", synthWaveShakeEnabled)
            putBoolean("synthwave_performance_mode", synthWavePerformanceMode)
            
            apply()
        }
    }
    
    /**
     * Export to JSON
     */
    fun toJson(): String {
        val json = JSONObject()
        
        json.put("version", VERSION)
        json.put("primaryColor", primaryColor)
        json.put("accentColor", accentColor)
        json.put("backgroundColor", backgroundColor)
        json.put("textPrimaryColor", textPrimaryColor)
        json.put("textSecondaryColor", textSecondaryColor)
        
        json.put("fontScale", fontScale)
        json.put("titleBold", titleBold)
        
        json.put("buttonSizeScale", buttonSizeScale)
        json.put("cardCornerRadiusDp", cardCornerRadiusDp)
        json.put("shadowsEnabled", shadowsEnabled)
        json.put("shadowIntensity", shadowIntensity)
        
        json.put("backgroundImageUri", backgroundImageUri)
        json.put("backgroundBlurRadius", backgroundBlurRadius)
        json.put("backgroundDimPercent", backgroundDimPercent)
        json.put("useSolidBackgroundColor", useSolidBackgroundColor)
        
        json.put("animationsEnabled", animationsEnabled)
        json.put("animationSpeed", animationSpeed.name)
        
        json.put("miniPlayerHeightDp", miniPlayerHeightDp)
        json.put("miniPlayerShowArt", miniPlayerShowArt)
        json.put("miniPlayerShowArtist", miniPlayerShowArtist)
        json.put("miniPlayerCompactMode", miniPlayerCompactMode)
        json.put("miniPlayerSpinningArt", miniPlayerSpinningArt)
        
        json.put("synthWaveEnabled", synthWaveEnabled)
        json.put("synthWaveProgressMode", synthWaveProgressMode)
        json.put("synthWaveUseCustomColors", synthWaveUseCustomColors)
        json.put("synthWavePrimaryColor", synthWavePrimaryColor)
        json.put("synthWaveSecondaryColor", synthWaveSecondaryColor)
        json.put("synthWaveGlowColor", synthWaveGlowColor)
        json.put("synthWaveAnimationIntensity", synthWaveAnimationIntensity)
        json.put("synthWaveParticleCount", synthWaveParticleCount)
        json.put("synthWaveFrequencyBands", synthWaveFrequencyBands)
        json.put("synthWaveLightningEnabled", synthWaveLightningEnabled)
        json.put("synthWaveRippleEnabled", synthWaveRippleEnabled)
        json.put("synthWaveShakeEnabled", synthWaveShakeEnabled)
        json.put("synthWavePerformanceMode", synthWavePerformanceMode)
        
        return json.toString(2)
    }
    
    /**
     * Calculate contrast ratio between two colors
     */
    fun calculateContrastRatio(color1: Int, color2: Int): Double {
        val luminance1 = calculateLuminance(color1)
        val luminance2 = calculateLuminance(color2)
        
        val lighter = maxOf(luminance1, luminance2)
        val darker = minOf(luminance1, luminance2)
        
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    private fun calculateLuminance(color: Int): Double {
        val r = android.graphics.Color.red(color) / 255.0
        val g = android.graphics.Color.green(color) / 255.0
        val b = android.graphics.Color.blue(color) / 255.0
        
        val rL = if (r <= 0.03928) r / 12.92 else Math.pow((r + 0.055) / 1.055, 2.4)
        val gL = if (g <= 0.03928) g / 12.92 else Math.pow((g + 0.055) / 1.055, 2.4)
        val bL = if (b <= 0.03928) b / 12.92 else Math.pow((b + 0.055) / 1.055, 2.4)
        
        return 0.2126 * rL + 0.7152 * gL + 0.0722 * bL
    }
    
    /**
     * Check if text colors have sufficient contrast
     */
    fun hasGoodContrast(): Boolean {
        val primaryContrast = calculateContrastRatio(textPrimaryColor, backgroundColor)
        val secondaryContrast = calculateContrastRatio(textSecondaryColor, backgroundColor)
        
        // WCAG AA requires 4.5:1 for normal text
        return primaryContrast >= 4.5 && secondaryContrast >= 3.0
    }
}
