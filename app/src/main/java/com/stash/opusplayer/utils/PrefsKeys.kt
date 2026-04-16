package com.stash.opusplayer.utils

object PrefsKeys {
    // Per-screen overrides
    const val SONGS_VIEW_COLUMNS = "songs_view_columns"              // Int: 1,2,3
    const val FOLDERS_VIEW_COLUMNS = "folders_view_columns"          // Int: 1,2,3 (top-level Folders)
    const val FOLDER_DETAIL_VIEW_COLUMNS = "folder_detail_view_columns" // Int: 1,2,3

    // Defaults in Settings
    const val DEFAULT_SONGS_VIEW_COLUMNS = "default_songs_view_columns"          // Int: 1,2,3
    const val DEFAULT_FOLDERS_VIEW_COLUMNS = "default_folders_view_columns"      // Int: 1,2,3
    const val DEFAULT_FOLDER_DETAIL_VIEW_COLUMNS = "default_folder_detail_view_columns" // Int: 1,2,3

    // Audio
    const val APP_VOLUME = "app_volume" // Float [0..1] in UI space (pre-mapping)

    // Appearance - Colors
    const val APPEARANCE_PRIMARY_COLOR = "appearance_primary_color"
    const val APPEARANCE_ACCENT_COLOR = "appearance_accent_color"
    const val APPEARANCE_BACKGROUND_COLOR = "appearance_background_color"
    const val APPEARANCE_TEXT_PRIMARY_COLOR = "appearance_text_primary_color"
    const val APPEARANCE_TEXT_SECONDARY_COLOR = "appearance_text_secondary_color"

    // Appearance - Typography
    const val APPEARANCE_FONT_SCALE = "appearance_font_scale"
    const val APPEARANCE_TITLE_BOLD = "appearance_title_bold"

    // Appearance - UI Elements
    const val APPEARANCE_BUTTON_SIZE_SCALE = "appearance_button_size_scale"
    const val APPEARANCE_CARD_CORNER_RADIUS_DP = "appearance_card_corner_radius_dp"
    const val APPEARANCE_SHADOWS_ENABLED = "appearance_shadows_enabled"
    const val APPEARANCE_SHADOW_INTENSITY = "appearance_shadow_intensity"

    // Appearance - Background
    const val APPEARANCE_BACKGROUND_IMAGE_URI = "background_image_uri" // Reuse existing key
    const val APPEARANCE_BACKGROUND_BLUR_RADIUS = "appearance_background_blur_radius"
    const val APPEARANCE_BACKGROUND_DIM_PERCENT = "appearance_background_dim_percent"
    const val APPEARANCE_BACKGROUND_USE_SOLID_COLOR = "appearance_background_use_solid_color"

    // Appearance - Animations
    const val APPEARANCE_ANIMATIONS_ENABLED = "appearance_animations_enabled"
    const val APPEARANCE_ANIMATION_SPEED = "appearance_animation_speed"

    // Appearance - Mini Player
    const val APPEARANCE_MINI_PLAYER_HEIGHT_DP = "appearance_mini_player_height_dp"
    const val APPEARANCE_MINI_PLAYER_SHOW_ART = "appearance_mini_player_show_art"
    const val APPEARANCE_MINI_PLAYER_SHOW_ARTIST = "appearance_mini_player_show_artist"
    const val APPEARANCE_MINI_PLAYER_COMPACT_MODE = "appearance_mini_player_compact_mode"
    const val APPEARANCE_MINI_PLAYER_SPINNING_ART = "appearance_mini_player_spinning_art"
    const val APPEARANCE_NOW_PLAYING_LAYOUT = "appearance_now_playing_layout"
    
    // Appearance - SynthWave Visualizer
    const val APPEARANCE_SYNTHWAVE_PROGRESS_MODE = "appearance_synthwave_progress_mode"
    const val APPEARANCE_SYNTHWAVE_USE_CUSTOM_COLORS = "appearance_synthwave_use_custom_colors"
    const val APPEARANCE_SYNTHWAVE_PRIMARY_COLOR = "appearance_synthwave_primary_color"
    const val APPEARANCE_SYNTHWAVE_SECONDARY_COLOR = "appearance_synthwave_secondary_color"
    const val APPEARANCE_SYNTHWAVE_GLOW_COLOR = "appearance_synthwave_glow_color"

    // Appearance - Bookkeeping
    const val APPEARANCE_RECENT_COLORS_JSON = "appearance_recent_colors_json"
    const val APPEARANCE_LAST_PRESET_NAME = "appearance_last_preset_name"
}

object PrefsUtils {
    fun resolveColumnsForScreen(prefs: android.content.SharedPreferences, perScreenKey: String, defaultKey: String, hardDefault: Int = 1): Int {
        val perScreen = prefs.getInt(perScreenKey, -1)
        if (perScreen != -1) return perScreen.coerceIn(1, 3)
        val def = prefs.getInt(defaultKey, -1)
        if (def != -1) return def.coerceIn(1, 3)
        return hardDefault
    }
}
