package com.stash.stashwave.utils

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