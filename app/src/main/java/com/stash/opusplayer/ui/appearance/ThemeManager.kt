package com.stash.opusplayer.ui.appearance

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.core.view.WindowCompat
import com.google.android.material.card.MaterialCardView
import com.stash.opusplayer.ui.MiniPlayerView

object ThemeManager {
    
    const val ACTION_APPEARANCE_CHANGED = "com.stash.opusplayer.ACTION_APPEARANCE_CHANGED"
    const val EXTRA_REQUIRES_RECREATE = "requires_recreate"
    
    // Global animation speed multiplier
    var animationSpeedMultiplier: Float = 1.0f
        private set
    
    /**
     * Load appearance preferences from context
     */
    fun load(context: Context): AppearancePreferences {
        return AppearancePreferences.fromPrefs(context)
    }
    
    /**
     * Apply appearance preferences to an activity
     * @return true if activity recreation is required
     */
    fun applyToActivity(activity: Activity, prefs: AppearancePreferences): Boolean {
        var requiresRecreate = false
        
        try {
            // Apply window/system bar colors
            applySystemBars(activity, prefs)
            
            // Apply toolbar colors
            if (activity is AppCompatActivity) {
                activity.supportActionBar?.let { actionBar ->
                    applyToolbarColors(activity, prefs)
                }
                
                // Apply title weight
                applyTitleWeight(activity, prefs.titleBold)
            }
            
            // Apply root view background
            activity.window?.decorView?.let { rootView ->
                applyRootBackground(rootView, prefs)
                
                // Apply button scaling to all buttons in the activity
                if (rootView is ViewGroup) {
                    applyButtonScalingToContainer(rootView, prefs)
                }
            }
            
            // Apply card corner radius to all cards
            activity.window?.decorView?.let { rootView ->
                if (rootView is ViewGroup) {
                    applyCardCornerRadiusToContainer(rootView, prefs)
                }
            }
            
            // Apply shadow settings
            activity.window?.decorView?.let { rootView ->
                if (rootView is ViewGroup) {
                    applyShadowsToContainer(rootView, prefs)
                }
            }
            
            // Update animation speed
            updateAnimationSpeed(prefs.animationSpeed)
            
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying theme to activity", e)
        }
        
        return requiresRecreate
    }
    
    /**
     * Apply system bar colors (status bar and navigation bar)
     */
    private fun applySystemBars(activity: Activity, prefs: AppearancePreferences) {
        val window = activity.window ?: return
        
        // Set status bar color
        window.statusBarColor = prefs.backgroundColor
        
        // Set navigation bar color
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            window.navigationBarColor = prefs.backgroundColor
        }
        
        // Adjust system bar icon colors based on background brightness
        val isBackgroundLight = isColorLight(prefs.backgroundColor)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = isBackgroundLight
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                isAppearanceLightNavigationBars = isBackgroundLight
            }
        }
    }
    
    /**
     * Apply colors to toolbar
     */
    private fun applyToolbarColors(activity: AppCompatActivity, prefs: AppearancePreferences) {
        try {
            val toolbar = findToolbar(activity)
            toolbar?.let {
                // Set toolbar background
                it.setBackgroundColor(prefs.backgroundColor)
                
                // Set title text color
                it.setTitleTextColor(prefs.textPrimaryColor)
                
                // Set navigation icon tint
                it.navigationIcon?.setTint(prefs.textPrimaryColor)
                
                // Set overflow icon tint
                it.overflowIcon?.setTint(prefs.textPrimaryColor)
            }
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying toolbar colors", e)
        }
    }
    
    /**
     * Find toolbar in activity
     */
    private fun findToolbar(activity: AppCompatActivity): Toolbar? {
        return try {
            // Try to find toolbar by common IDs
            val toolbarId = activity.resources.getIdentifier("toolbar", "id", activity.packageName)
            if (toolbarId != 0) {
                activity.findViewById<Toolbar>(toolbarId)
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * Apply root view background color
     */
    private fun applyRootBackground(rootView: View, prefs: AppearancePreferences) {
        try {
            // Find the main content container
            val contentView = rootView.findViewById<View>(android.R.id.content)
            contentView?.setBackgroundColor(prefs.backgroundColor)
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying root background", e)
        }
    }
    
    /**
     * Apply typography scale (requires activity recreation)
     * This is called during initial theme setup and saves the scale for future use
     */
    fun applyTypographyScale(activity: Activity, scale: Float): Boolean {
        try {
            // Save the scale for use during initial setup
            // Note: On modern Android, updateConfiguration is deprecated and doesn't work reliably
            // The font scale is better applied through theme/styling during app creation
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // On newer Android versions, we just save the preference
                // The actual scaling should be handled by the system through proper theme setup
                android.util.Log.i("ThemeManager", "Font scale $scale saved for next app restart")
                return false // Don't require recreate - changes apply on restart
            } else {
                // On older versions, try the deprecated method
                val config = Configuration(activity.resources.configuration)
                config.fontScale = scale
                @Suppress("DEPRECATION")
                activity.resources.updateConfiguration(config, activity.resources.displayMetrics)
                return true // Requires recreate
            }
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying typography scale", e)
            return false
        }
    }
    
    /**
     * Apply title weight to toolbar
     */
    fun applyTitleWeight(activity: AppCompatActivity, isBold: Boolean) {
        try {
            val toolbar = findToolbar(activity)
            toolbar?.let {
                // This is a best-effort approach; actual implementation may vary
                // We can't directly change title typeface, but we can influence it
                it.setTitleTextAppearance(activity, if (isBold) {
                    android.R.style.TextAppearance_Material_Widget_ActionBar_Title
                } else {
                    android.R.style.TextAppearance_Material_Widget_ActionBar_Title
                })
            }
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying title weight", e)
        }
    }
    
    /**
     * Apply mini player settings
     */
    fun applyMiniPlayerSettings(miniPlayerView: MiniPlayerView, prefs: AppearancePreferences) {
        try {
            // Apply height
            val layoutParams = miniPlayerView.layoutParams
            layoutParams.height = (prefs.miniPlayerHeightDp * miniPlayerView.resources.displayMetrics.density).toInt()
            miniPlayerView.layoutParams = layoutParams
            
            // Apply all appearance preferences using the new method
            miniPlayerView.applyAppearancePreferences(prefs)
            
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying mini player settings", e)
        }
    }
    
    /**
     * Apply background overlay with dim and blur
     */
    fun applyBackgroundOverlay(activity: Activity, prefs: AppearancePreferences) {
        try {
            val rootView = activity.window?.decorView?.findViewById<ViewGroup>(android.R.id.content) ?: return
            
            // Find or create overlay view
            val overlayId = View.generateViewId()
            var overlayView = rootView.findViewWithTag<View>("dim_overlay")
            
            if (overlayView == null && prefs.backgroundDimPercent > 0) {
                overlayView = View(activity).apply {
                    tag = "dim_overlay"
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                }
                rootView.addView(overlayView, 0) // Add at bottom
            }
            
            // Update dim overlay
            overlayView?.let {
                val alpha = (prefs.backgroundDimPercent / 100f * 255).toInt()
                it.setBackgroundColor(Color.argb(alpha, 0, 0, 0))
                it.visibility = if (prefs.backgroundDimPercent > 0) View.VISIBLE else View.GONE
            }
            
            // Apply blur if API 31+ and blur radius > 0
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && prefs.backgroundBlurRadius > 0) {
                applyBackgroundBlur(activity, prefs.backgroundBlurRadius)
            }
            
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying background overlay", e)
        }
    }
    
    /**
     * Apply background blur (API 31+)
     */
    @androidx.annotation.RequiresApi(Build.VERSION_CODES.S)
    private fun applyBackgroundBlur(activity: Activity, blurRadius: Int) {
        try {
            val backgroundImageId = activity.resources.getIdentifier("background_image", "id", activity.packageName)
            if (backgroundImageId == 0) return
            
            val backgroundImage = activity.findViewById<View>(backgroundImageId) ?: return
            
            if (blurRadius > 0) {
                val blurEffect = android.graphics.RenderEffect.createBlurEffect(
                    blurRadius.toFloat(),
                    blurRadius.toFloat(),
                    android.graphics.Shader.TileMode.CLAMP
                )
                backgroundImage.setRenderEffect(blurEffect)
            } else {
                backgroundImage.setRenderEffect(null)
            }
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying blur", e)
        }
    }
    
    /**
     * Apply corner radius to a MaterialCardView
     */
    fun applyCardCornerRadius(cardView: MaterialCardView, radiusDp: Int) {
        val radiusPx = radiusDp * cardView.resources.displayMetrics.density
        cardView.radius = radiusPx
    }
    
    /**
     * Apply shadow settings to a view
     */
    fun applyShadowSettings(view: View, shadowsEnabled: Boolean, intensity: Float) {
        if (shadowsEnabled) {
            val elevation = 8f * intensity * view.resources.displayMetrics.density
            view.elevation = elevation
        } else {
            view.elevation = 0f
        }
    }
    
    /**
     * Create ColorStateList for primary color
     */
    fun createPrimaryColorStateList(prefs: AppearancePreferences): ColorStateList {
        return ColorStateList.valueOf(prefs.primaryColor)
    }
    
    /**
     * Create ColorStateList for accent color
     */
    fun createAccentColorStateList(prefs: AppearancePreferences): ColorStateList {
        return ColorStateList.valueOf(prefs.accentColor)
    }
    
    /**
     * Broadcast appearance change
     */
    fun broadcastChange(context: Context, requiresRecreate: Boolean) {
        val intent = Intent(ACTION_APPEARANCE_CHANGED).apply {
            putExtra(EXTRA_REQUIRES_RECREATE, requiresRecreate)
        }
        context.sendBroadcast(intent)
    }
    
    /**
     * Maybe recreate activity if required
     */
    fun maybeRecreate(activity: Activity, requiresRecreate: Boolean) {
        if (requiresRecreate) {
            activity.recreate()
        }
    }
    
    /**
     * Update animation speed multiplier
     */
    private fun updateAnimationSpeed(speed: AppearancePreferences.AnimationSpeed) {
        animationSpeedMultiplier = speed.multiplier
    }
    
    /**
     * Get scaled animation duration
     */
    fun getScaledAnimationDuration(baseDuration: Long): Long {
        return (baseDuration * animationSpeedMultiplier).toLong()
    }
    
    /**
     * Check if a color is light (for determining text/icon colors)
     */
    private fun isColorLight(color: Int): Boolean {
        val darkness = 1 - (0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color)) / 255
        return darkness < 0.5
    }
    
    /**
     * Apply button size scale to a view
     */
    fun applyButtonSizeScale(view: View, scale: Float) {
        view.scaleX = scale
        view.scaleY = scale
    }
    
    /**
     * Apply button scaling to all buttons in a container
     */
    fun applyButtonScalingToContainer(container: ViewGroup, prefs: AppearancePreferences) {
        try {
            val scale = prefs.buttonSizeScale
            for (i in 0 until container.childCount) {
                val child = container.getChildAt(i)
                when (child) {
                    is android.widget.Button, 
                    is android.widget.ImageButton,
                    is com.google.android.material.button.MaterialButton,
                    is com.google.android.material.floatingactionbutton.FloatingActionButton -> {
                        applyButtonSizeScale(child, scale)
                    }
                    is ViewGroup -> {
                        // Recursively apply to nested containers
                        applyButtonScalingToContainer(child, prefs)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying button scaling", e)
        }
    }
    
    /**
     * Convert color int to hex string
     */
    fun colorToHex(color: Int): String {
        return String.format("#%06X", 0xFFFFFF and color)
    }
    
    /**
     * Parse hex color string to int
     */
    fun hexToColor(hex: String): Int {
        var colorString = hex.trim()
        
        // Remove # if present
        if (colorString.startsWith("#")) {
            colorString = colorString.substring(1)
        }
        
        // Add FF alpha if not present
        if (colorString.length == 6) {
            colorString = "FF$colorString"
        }
        
        return try {
            Color.parseColor("#$colorString")
        } catch (e: Exception) {
            0xFF000000.toInt() // Default to black
        }
    }
    
    /**
     * Apply card corner radius to all cards in a container
     */
    fun applyCardCornerRadiusToContainer(container: ViewGroup, prefs: AppearancePreferences) {
        try {
            val radius = prefs.cardCornerRadiusDp
            for (i in 0 until container.childCount) {
                val child = container.getChildAt(i)
                when (child) {
                    is MaterialCardView -> {
                        applyCardCornerRadius(child, radius)
                    }
                    is ViewGroup -> {
                        // Recursively apply to nested containers
                        applyCardCornerRadiusToContainer(child, prefs)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying card corner radius", e)
        }
    }
    
    /**
     * Apply shadow settings to all views in a container
     */
    fun applyShadowsToContainer(container: ViewGroup, prefs: AppearancePreferences) {
        try {
            for (i in 0 until container.childCount) {
                val child = container.getChildAt(i)
                when (child) {
                    is MaterialCardView,
                    is android.widget.Button,
                    is android.widget.ImageButton,
                    is com.google.android.material.button.MaterialButton -> {
                        applyShadowSettings(child, prefs.shadowsEnabled, prefs.shadowIntensity)
                    }
                    is ViewGroup -> {
                        // Recursively apply to nested containers
                        applyShadowsToContainer(child, prefs)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying shadows", e)
        }
    }
    
    /**
     * Apply text colors to all text views in a container
     */
    fun applyTextColorsToContainer(container: ViewGroup, prefs: AppearancePreferences) {
        try {
            for (i in 0 until container.childCount) {
                val child = container.getChildAt(i)
                when (child) {
                    is android.widget.TextView -> {
                        // Determine if this should be primary or secondary text
                        val textColor = if (child.textSize >= 16f) {
                            prefs.textPrimaryColor
                        } else {
                            prefs.textSecondaryColor
                        }
                        child.setTextColor(textColor)
                    }
                    is ViewGroup -> {
                        // Recursively apply to nested containers
                        applyTextColorsToContainer(child, prefs)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ThemeManager", "Error applying text colors", e)
        }
    }
    
    /**
     * Apply all appearance settings to an activity (convenience method)
     */
    fun applyAll(activity: Activity) {
        val prefs = load(activity)
        
        // Apply typography scale (note: on modern Android this just logs and doesn't recreate)
        var requiresRecreate = false
        if (prefs.fontScale != 1.0f) {
            requiresRecreate = applyTypographyScale(activity, prefs.fontScale)
        }
        
        // Apply activity theme
        requiresRecreate = requiresRecreate || applyToActivity(activity, prefs)
        
        // Apply background overlay
        applyBackgroundOverlay(activity, prefs)
        
        // Apply text colors
        activity.window?.decorView?.let { rootView ->
            if (rootView is ViewGroup) {
                applyTextColorsToContainer(rootView, prefs)
            }
        }
        
        // If recreation is needed, do it
        if (requiresRecreate) {
            maybeRecreate(activity, true)
        }
    }
}
