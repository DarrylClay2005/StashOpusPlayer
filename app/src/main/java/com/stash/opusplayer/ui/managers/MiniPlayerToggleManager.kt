package com.stash.opusplayer.ui.managers

import android.content.Context
import android.content.SharedPreferences
import android.view.ViewGroup
import androidx.preference.PreferenceManager
import com.stash.opusplayer.ui.MiniPlayerView
import com.stash.opusplayer.ui.views.RevampedMiniPlayerView

/**
 * Manages toggling between old and new mini player versions
 */
class MiniPlayerToggleManager(private val context: Context) {
    
    companion object {
        private const val PREF_USE_REVAMPED_MINI_PLAYER = "use_revamped_mini_player"
        private const val PREF_MINI_PLAYER_STYLE = "mini_player_style"
        
        // Mini player styles
        const val STYLE_CLASSIC = "classic"
        const val STYLE_REVAMPED = "revamped"
        const val STYLE_COMPACT = "compact"
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    /**
     * Get the current mini player preference
     */
    fun shouldUseRevampedMiniPlayer(): Boolean {
        return prefs.getBoolean(PREF_USE_REVAMPED_MINI_PLAYER, true)
    }
    
    /**
     * Set mini player preference
     */
    fun setUseRevampedMiniPlayer(useRevamped: Boolean) {
        prefs.edit()
            .putBoolean(PREF_USE_REVAMPED_MINI_PLAYER, useRevamped)
            .apply()
    }
    
    /**
     * Get current mini player style
     */
    fun getMiniPlayerStyle(): String {
        return prefs.getString(PREF_MINI_PLAYER_STYLE, STYLE_REVAMPED) ?: STYLE_REVAMPED
    }
    
    /**
     * Set mini player style
     */
    fun setMiniPlayerStyle(style: String) {
        prefs.edit()
            .putString(PREF_MINI_PLAYER_STYLE, style)
            .putBoolean(PREF_USE_REVAMPED_MINI_PLAYER, style != STYLE_CLASSIC)
            .apply()
    }
    
    /**
     * Create the appropriate mini player view based on preferences
     */
    fun createMiniPlayerView(parent: ViewGroup): Any {
        return when (getMiniPlayerStyle()) {
            STYLE_REVAMPED -> {
                RevampedMiniPlayerView(context).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                }
            }
            STYLE_COMPACT -> {
                // Could create a compact version
                createCompactMiniPlayer()
            }
            else -> {
                // Classic/fallback
                MiniPlayerView(context).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                }
            }
        }
    }
    
    private fun createCompactMiniPlayer(): RevampedMiniPlayerView {
        // Create a more compact version of the revamped player
        return RevampedMiniPlayerView(context).apply {
            // Could apply different styling or configuration
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            alpha = 0.95f // Slightly transparent for compact feel
        }
    }
    
    /**
     * Get available mini player styles with display names
     */
    fun getAvailableStyles(): List<Pair<String, String>> {
        return listOf(
            STYLE_CLASSIC to "Classic Mini Player",
            STYLE_REVAMPED to "Revamped Mini Player", 
            STYLE_COMPACT to "Compact Mini Player"
        )
    }
    
    /**
     * Get features available for each style
     */
    fun getStyleFeatures(style: String): List<String> {
        return when (style) {
            STYLE_CLASSIC -> listOf(
                "Basic controls",
                "Album art display",
                "Track information",
                "Simple progress bar"
            )
            STYLE_REVAMPED -> listOf(
                "Enhanced gesture controls",
                "Advanced swipe gestures",
                "Mini visualizer overlay",
                "Smooth animations",
                "Double-tap controls",
                "Long-press options menu",
                "Rotating album art",
                "Pulse effects"
            )
            STYLE_COMPACT -> listOf(
                "Minimal footprint",
                "Essential controls only",
                "Gesture support",
                "Quick access"
            )
            else -> emptyList()
        }
    }
    
    /**
     * Check if a specific feature is supported by the current style
     */
    fun isFeatureSupported(feature: String): Boolean {
        val currentStyle = getMiniPlayerStyle()
        return when (feature) {
            "gestures" -> currentStyle != STYLE_CLASSIC
            "visualizer" -> currentStyle == STYLE_REVAMPED
            "animations" -> currentStyle != STYLE_CLASSIC
            "double_tap" -> currentStyle == STYLE_REVAMPED
            "long_press_menu" -> currentStyle == STYLE_REVAMPED
            "album_art_rotation" -> currentStyle == STYLE_REVAMPED
            "pulse_effects" -> currentStyle == STYLE_REVAMPED
            else -> true // Basic features supported by all
        }
    }
}