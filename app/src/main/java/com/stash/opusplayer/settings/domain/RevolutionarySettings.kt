package com.stash.opusplayer.settings.domain

import android.content.Context
import android.content.SharedPreferences
import androidx.preference.PreferenceManager

/**
 * Revolutionary Settings System
 */

data class RevolutionarySettings(
    val audioSettings: AudioSettings = AudioSettings(),
    val aiSettings: AISettings = AISettings(),
    val metadataSettings: MetadataSettings = MetadataSettings(),
    val uiSettings: UISettings = UISettings(),
    val miniPlayerSettings: MiniPlayerSettings = MiniPlayerSettings()
)

data class AudioSettings(
    val audioEngine: String = "revolutionary",
    val enable8DAudio: Boolean = false,
    val audioIntensity: Float = 0.7f,
    val audioSpeed: Float = 1.0f,
    val enableGaplessPlayback: Boolean = true,
    val enableCrossfade: Boolean = false,
    val crossfadeDuration: Float = 3.0f,
    val audioQuality: String = "high"
)

data class AISettings(
    val enableAIAnalysis: Boolean = true,
    val enableRealtimeAnalysis: Boolean = false,
    val enableGenreClassification: Boolean = true,
    val enableMoodAnalysis: Boolean = true,
    val enableAudioAnalysis: Boolean = true,
    val aiProcessingQuality: String = "balanced"
)

data class MetadataSettings(
    val enableBackgroundEnhancement: Boolean = true,
    val enableOnlineMetadata: Boolean = true,
    val enableArtworkFetching: Boolean = true,
    val metadataQuality: String = "high"
)

data class UISettings(
    val theme: String = "dynamic",
    val enableDynamicColors: Boolean = true,
    val enableAnimations: Boolean = true,
    val composeUI: Boolean = true
)

data class MiniPlayerSettings(
    val style: String = "modern",
    val showProgress: Boolean = true,
    val enableGestures: Boolean = true,
    val showAlbumArt: Boolean = true,
    val compactMode: Boolean = false
)

/**
 * Settings Repository
 */
class RevolutionarySettingsRepository(
    private val context: Context
) {
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    fun getSettings(): RevolutionarySettings {
        return RevolutionarySettings(
            audioSettings = getAudioSettings(),
            aiSettings = getAISettings(),
            metadataSettings = getMetadataSettings(),
            uiSettings = getUISettings(),
            miniPlayerSettings = getMiniPlayerSettings()
        )
    }
    
    fun saveSettings(settings: RevolutionarySettings) {
        saveAudioSettings(settings.audioSettings)
        saveAISettings(settings.aiSettings)
        saveMetadataSettings(settings.metadataSettings)
        saveUISettings(settings.uiSettings)
        saveMiniPlayerSettings(settings.miniPlayerSettings)
    }
    
    private fun getAudioSettings(): AudioSettings {
        return AudioSettings(
            audioEngine = prefs.getString("audio_engine", "revolutionary") ?: "revolutionary",
            enable8DAudio = prefs.getBoolean("enable_8d_audio", false),
            audioIntensity = prefs.getFloat("audio_intensity", 0.7f),
            audioSpeed = prefs.getFloat("audio_speed", 1.0f),
            enableGaplessPlayback = prefs.getBoolean("enable_gapless", true),
            enableCrossfade = prefs.getBoolean("enable_crossfade", false),
            crossfadeDuration = prefs.getFloat("crossfade_duration", 3.0f),
            audioQuality = prefs.getString("audio_quality", "high") ?: "high"
        )
    }
    
    private fun getAISettings(): AISettings {
        return AISettings(
            enableAIAnalysis = prefs.getBoolean("enable_ai_analysis", true),
            enableRealtimeAnalysis = prefs.getBoolean("enable_realtime_analysis", false),
            enableGenreClassification = prefs.getBoolean("enable_genre_classification", true),
            enableMoodAnalysis = prefs.getBoolean("enable_mood_analysis", true),
            enableAudioAnalysis = prefs.getBoolean("enable_audio_analysis", true),
            aiProcessingQuality = prefs.getString("ai_processing_quality", "balanced") ?: "balanced"
        )
    }
    
    private fun getMetadataSettings(): MetadataSettings {
        return MetadataSettings(
            enableBackgroundEnhancement = prefs.getBoolean("enable_background_metadata", true),
            enableOnlineMetadata = prefs.getBoolean("enable_online_metadata", true),
            enableArtworkFetching = prefs.getBoolean("enable_artwork_fetching", true),
            metadataQuality = prefs.getString("metadata_quality", "high") ?: "high"
        )
    }
    
    private fun getUISettings(): UISettings {
        return UISettings(
            theme = prefs.getString("ui_theme", "dynamic") ?: "dynamic",
            enableDynamicColors = prefs.getBoolean("enable_dynamic_colors", true),
            enableAnimations = prefs.getBoolean("enable_animations", true),
            composeUI = prefs.getBoolean("compose_ui", true)
        )
    }
    
    private fun getMiniPlayerSettings(): MiniPlayerSettings {
        return MiniPlayerSettings(
            style = prefs.getString("miniplayer_style", "modern") ?: "modern",
            showProgress = prefs.getBoolean("miniplayer_show_progress", true),
            enableGestures = prefs.getBoolean("miniplayer_gestures", true),
            showAlbumArt = prefs.getBoolean("miniplayer_show_art", true),
            compactMode = prefs.getBoolean("miniplayer_compact", false)
        )
    }
    
    private fun saveAudioSettings(settings: AudioSettings) {
        prefs.edit()
            .putString("audio_engine", settings.audioEngine)
            .putBoolean("enable_8d_audio", settings.enable8DAudio)
            .putFloat("audio_intensity", settings.audioIntensity)
            .putFloat("audio_speed", settings.audioSpeed)
            .putBoolean("enable_gapless", settings.enableGaplessPlayback)
            .putBoolean("enable_crossfade", settings.enableCrossfade)
            .putFloat("crossfade_duration", settings.crossfadeDuration)
            .putString("audio_quality", settings.audioQuality)
            .apply()
    }
    
    private fun saveAISettings(settings: AISettings) {
        prefs.edit()
            .putBoolean("enable_ai_analysis", settings.enableAIAnalysis)
            .putBoolean("enable_realtime_analysis", settings.enableRealtimeAnalysis)
            .putBoolean("enable_genre_classification", settings.enableGenreClassification)
            .putBoolean("enable_mood_analysis", settings.enableMoodAnalysis)
            .putBoolean("enable_audio_analysis", settings.enableAudioAnalysis)
            .putString("ai_processing_quality", settings.aiProcessingQuality)
            .apply()
    }
    
    private fun saveMetadataSettings(settings: MetadataSettings) {
        prefs.edit()
            .putBoolean("enable_background_metadata", settings.enableBackgroundEnhancement)
            .putBoolean("enable_online_metadata", settings.enableOnlineMetadata)
            .putBoolean("enable_artwork_fetching", settings.enableArtworkFetching)
            .putString("metadata_quality", settings.metadataQuality)
            .apply()
    }
    
    private fun saveUISettings(settings: UISettings) {
        prefs.edit()
            .putString("ui_theme", settings.theme)
            .putBoolean("enable_dynamic_colors", settings.enableDynamicColors)
            .putBoolean("enable_animations", settings.enableAnimations)
            .putBoolean("compose_ui", settings.composeUI)
            .apply()
    }
    
    private fun saveMiniPlayerSettings(settings: MiniPlayerSettings) {
        prefs.edit()
            .putString("miniplayer_style", settings.style)
            .putBoolean("miniplayer_show_progress", settings.showProgress)
            .putBoolean("miniplayer_gestures", settings.enableGestures)
            .putBoolean("miniplayer_show_art", settings.showAlbumArt)
            .putBoolean("miniplayer_compact", settings.compactMode)
            .apply()
    }
}