package com.stash.opusplayer.ui.appearance

import android.content.Context

object AppearancePresets {
    
    data class PresetInfo(
        val id: String,
        val name: String,
        val primaryColor: Int,
        val accentColor: Int,
        val backgroundColor: Int,
        val textPrimaryColor: Int,
        val textSecondaryColor: Int
    )
    
    /**
     * Predefined theme presets with carefully chosen contrasting colors
     */
    private val PRESETS = listOf(
        PresetInfo(
            id = "dark_blue",
            name = "Dark Blue (Default)",
            primaryColor = 0xFF4A5568.toInt(),
            accentColor = 0xFFEC407A.toInt(),
            backgroundColor = 0xFF2D3748.toInt(),
            textPrimaryColor = 0xFFF7FAFC.toInt(),
            textSecondaryColor = 0xFFCBD5E0.toInt()
        ),
        PresetInfo(
            id = "cyberpunk_pink",
            name = "Cyberpunk Pink",
            primaryColor = 0xFF0D0221.toInt(),
            accentColor = 0xFFFF2D95.toInt(),
            backgroundColor = 0xFF05010A.toInt(),
            textPrimaryColor = 0xFFFFFFFF.toInt(),
            textSecondaryColor = 0xFF9E9E9E.toInt()
        ),
        PresetInfo(
            id = "forest_green",
            name = "Forest Green",
            primaryColor = 0xFF2E7D32.toInt(),
            accentColor = 0xFFA5D6A7.toInt(),
            backgroundColor = 0xFF0F2E17.toInt(),
            textPrimaryColor = 0xFFE8F5E9.toInt(),
            textSecondaryColor = 0xFFC8E6C9.toInt()
        ),
        PresetInfo(
            id = "oled_black",
            name = "OLED Black",
            primaryColor = 0xFF121212.toInt(),
            accentColor = 0xFF00E5FF.toInt(),
            backgroundColor = 0xFF000000.toInt(),
            textPrimaryColor = 0xFFFFFFFF.toInt(),
            textSecondaryColor = 0xFFB3B3B3.toInt()
        ),
        PresetInfo(
            id = "sunset_orange",
            name = "Sunset Orange",
            primaryColor = 0xFFFF7043.toInt(),
            accentColor = 0xFFFFB300.toInt(),
            backgroundColor = 0xFF2B1B14.toInt(),
            textPrimaryColor = 0xFFFFF8E1.toInt(),
            textSecondaryColor = 0xFFFFCC80.toInt()
        ),
        PresetInfo(
            id = "ocean_blue",
            name = "Ocean Blue",
            primaryColor = 0xFF1565C0.toInt(),
            accentColor = 0xFF26C6DA.toInt(),
            backgroundColor = 0xFF0A1E3A.toInt(),
            textPrimaryColor = 0xFFE3F2FD.toInt(),
            textSecondaryColor = 0xFF90CAF9.toInt()
        )
    )
    
    /**
     * Get list of all available presets
     */
    fun listPresets(): List<PresetInfo> = PRESETS
    
    /**
     * Get preset by ID
     */
    fun getPreset(id: String): PresetInfo? {
        return PRESETS.find { it.id == id }
    }
    
    /**
     * Apply preset colors to current preferences
     * @return Updated AppearancePreferences with new colors
     */
    fun applyPresetColors(context: Context, presetId: String): AppearancePreferences? {
        val preset = getPreset(presetId) ?: return null
        val current = AppearancePreferences.fromPrefs(context)
        
        val updated = current.copy(
            primaryColor = preset.primaryColor,
            accentColor = preset.accentColor,
            backgroundColor = preset.backgroundColor,
            textPrimaryColor = preset.textPrimaryColor,
            textSecondaryColor = preset.textSecondaryColor
        )
        
        updated.saveToPrefs(context)
        return updated
    }
    
    /**
     * Create AppearancePreferences from a preset (full copy including all settings)
     */
    fun presetToAppearancePreferences(preset: PresetInfo, basePrefs: AppearancePreferences? = null): AppearancePreferences {
        val base = basePrefs ?: AppearancePreferences()
        
        return base.copy(
            primaryColor = preset.primaryColor,
            accentColor = preset.accentColor,
            backgroundColor = preset.backgroundColor,
            textPrimaryColor = preset.textPrimaryColor,
            textSecondaryColor = preset.textSecondaryColor
        )
    }
    
    /**
     * Custom preset management - Save a custom preset
     */
    fun saveCustomPreset(context: Context, name: String, prefs: AppearancePreferences) {
        val presetsPrefs = context.getSharedPreferences("appearance_presets", Context.MODE_PRIVATE)
        val json = prefs.toJson()
        
        presetsPrefs.edit()
            .putString(name, json)
            .apply()
    }
    
    /**
     * Get all saved custom preset names
     */
    fun getCustomPresetNames(context: Context): List<String> {
        val presetsPrefs = context.getSharedPreferences("appearance_presets", Context.MODE_PRIVATE)
        return presetsPrefs.all.keys.toList().sorted()
    }
    
    /**
     * Load a custom preset
     */
    fun loadCustomPreset(context: Context, name: String): AppearancePreferences? {
        val presetsPrefs = context.getSharedPreferences("appearance_presets", Context.MODE_PRIVATE)
        val json = presetsPrefs.getString(name, null) ?: return null
        
        return try {
            AppearancePreferences.fromJson(json)
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * Delete a custom preset
     */
    fun deleteCustomPreset(context: Context, name: String) {
        val presetsPrefs = context.getSharedPreferences("appearance_presets", Context.MODE_PRIVATE)
        presetsPrefs.edit().remove(name).apply()
    }
    
    /**
     * Check if a custom preset name already exists
     */
    fun customPresetExists(context: Context, name: String): Boolean {
        val presetsPrefs = context.getSharedPreferences("appearance_presets", Context.MODE_PRIVATE)
        return presetsPrefs.contains(name)
    }
}
