package com.stash.opusplayer.utils

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.util.DisplayMetrics
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import kotlin.math.min

/**
 * Utility class for responsive design and automatic UI scaling
 * Ensures the app fits properly on all screen sizes and densities
 */
object ResponsiveUtils {
    private const val TAG = "ResponsiveUtils"
    
    // Screen size categories
    enum class ScreenSize {
        SMALL,    // < 3.5 inches
        NORMAL,   // 3.5-4.5 inches  
        LARGE,    // 4.5-6.5 inches
        XLARGE    // > 6.5 inches
    }
    
    // Screen density categories  
    enum class ScreenDensity {
        LOW,      // ldpi (120 dpi)
        MEDIUM,   // mdpi (160 dpi)
        HIGH,     // hdpi (240 dpi)
        XHIGH,    // xhdpi (320 dpi)
        XXHIGH,   // xxhdpi (480 dpi)
        XXXHIGH   // xxxhdpi (640 dpi)
    }
    
    data class ScreenInfo(
        val size: ScreenSize,
        val density: ScreenDensity,
        val widthDp: Int,
        val heightDp: Int,
        val widthPx: Int,
        val heightPx: Int,
        val scaleFactor: Float
    )
    
    /**
     * Get comprehensive screen information
     */
    fun getScreenInfo(context: Context): ScreenInfo {
        val displayMetrics = context.resources.displayMetrics
        val configuration = context.resources.configuration
        
        // Calculate physical screen size in inches - with safety checks
        val widthInches = if (displayMetrics.xdpi > 0) displayMetrics.widthPixels / displayMetrics.xdpi else 4.0f
        val heightInches = if (displayMetrics.ydpi > 0) displayMetrics.heightPixels / displayMetrics.ydpi else 6.0f
        val diagonalInches = kotlin.math.sqrt((widthInches * widthInches + heightInches * heightInches).toDouble())
        
        val screenSize = when {
            diagonalInches < 3.5 -> ScreenSize.SMALL
            diagonalInches < 4.5 -> ScreenSize.NORMAL
            diagonalInches < 6.5 -> ScreenSize.LARGE
            else -> ScreenSize.XLARGE
        }
        
        val screenDensity = when (displayMetrics.densityDpi) {
            in 0..140 -> ScreenDensity.LOW
            in 141..200 -> ScreenDensity.MEDIUM
            in 201..280 -> ScreenDensity.HIGH
            in 281..400 -> ScreenDensity.XHIGH
            in 401..560 -> ScreenDensity.XXHIGH
            else -> ScreenDensity.XXXHIGH
        }
        
        // Calculate automatic scale factor based on screen characteristics
        val scaleFactor = calculateAutoScaleFactor(context, screenSize, screenDensity)
        
        val widthDp = (displayMetrics.widthPixels / displayMetrics.density).toInt()
        val heightDp = (displayMetrics.heightPixels / displayMetrics.density).toInt()
        
        return ScreenInfo(
            size = screenSize,
            density = screenDensity,
            widthDp = widthDp,
            heightDp = heightDp,
            widthPx = displayMetrics.widthPixels,
            heightPx = displayMetrics.heightPixels,
            scaleFactor = scaleFactor
        )
    }
    
    /**
     * Calculate automatic scale factor for optimal UI sizing
     */
    private fun calculateAutoScaleFactor(context: Context, screenSize: ScreenSize, screenDensity: ScreenDensity): Float {
        val displayMetrics = context.resources.displayMetrics
        val widthDp = displayMetrics.widthPixels / displayMetrics.density
        val heightDp = displayMetrics.heightPixels / displayMetrics.density
        
        // Base scale factor on screen width (more conservative scaling)
        val baseScale = when {
            widthDp < 320 -> 0.85f  // Very small screens
            widthDp < 360 -> 0.9f   // Small screens
            widthDp < 400 -> 0.95f  // Normal screens
            widthDp < 480 -> 1.0f   // Large screens
            widthDp < 600 -> 1.05f  // Extra large screens
            else -> 1.1f            // Tablet-sized screens
        }
        
        // More conservative density adjustment
        val densityAdjustment = when (screenDensity) {
            ScreenDensity.LOW -> 1.1f
            ScreenDensity.MEDIUM -> 1.05f
            ScreenDensity.HIGH -> 1.0f
            ScreenDensity.XHIGH -> 0.98f
            ScreenDensity.XXHIGH -> 0.95f
            ScreenDensity.XXXHIGH -> 0.92f
        }
        
        return (baseScale * densityAdjustment).coerceIn(0.8f, 1.2f) // Safety bounds
    }
    
    /**
     * Apply responsive scaling to a view's padding
     */
    fun applyResponsivePadding(view: View, basePadding: Int) {
        try {
            val screenInfo = getScreenInfo(view.context)
            val scaledPadding = (basePadding * screenInfo.scaleFactor).toInt().coerceIn(0, 200) // Safety bounds
            view.setPadding(scaledPadding, scaledPadding, scaledPadding, scaledPadding)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to apply responsive padding, using default", e)
            view.setPadding(basePadding, basePadding, basePadding, basePadding)
        }
    }
    
    /**
     * Apply responsive scaling to specific padding values
     */
    fun applyResponsivePadding(view: View, left: Int, top: Int, right: Int, bottom: Int) {
        val screenInfo = getScreenInfo(view.context)
        val scaledLeft = (left * screenInfo.scaleFactor).toInt()
        val scaledTop = (top * screenInfo.scaleFactor).toInt()
        val scaledRight = (right * screenInfo.scaleFactor).toInt()
        val scaledBottom = (bottom * screenInfo.scaleFactor).toInt()
        view.setPadding(scaledLeft, scaledTop, scaledRight, scaledBottom)
    }
    
    /**
     * Apply responsive scaling to text size
     */
    fun applyResponsiveTextSize(textView: TextView, baseTextSizeSp: Float) {
        try {
            val screenInfo = getScreenInfo(textView.context)
            val scaledTextSize = (baseTextSizeSp * screenInfo.scaleFactor).coerceIn(10f, 36f) // Safety bounds
            textView.textSize = scaledTextSize
        } catch (e: Exception) {
            Log.w(TAG, "Failed to apply responsive text size, using default", e)
            textView.textSize = baseTextSizeSp
        }
    }
    
    /**
     * Apply responsive margins to a view
     */
    fun applyResponsiveMargins(view: View, baseMargin: Int) {
        val screenInfo = getScreenInfo(view.context)
        val scaledMargin = (baseMargin * screenInfo.scaleFactor).toInt()
        
        val layoutParams = view.layoutParams
        if (layoutParams is ViewGroup.MarginLayoutParams) {
            layoutParams.setMargins(scaledMargin, scaledMargin, scaledMargin, scaledMargin)
            view.layoutParams = layoutParams
        }
    }
    
    /**
     * Check if tabs should be scrollable based on screen width
     */
    fun shouldUseScrollableTabs(context: Context, tabCount: Int): Boolean {
        val screenInfo = getScreenInfo(context)
        
        // Use scrollable tabs if:
        // 1. Screen width is less than 360dp, OR
        // 2. We have more than 3 tabs and width is less than 480dp
        return screenInfo.widthDp < 360 || (tabCount > 3 && screenInfo.widthDp < 480)
    }
    
    /**
     * Get optimal tab mode for current screen
     */
    fun getOptimalTabMode(context: Context, tabCount: Int): Int {
        return if (shouldUseScrollableTabs(context, tabCount)) {
            com.google.android.material.tabs.TabLayout.MODE_SCROLLABLE
        } else {
            com.google.android.material.tabs.TabLayout.MODE_FIXED
        }
    }
    
    /**
     * Get optimal tab gravity for current screen
     */
    fun getOptimalTabGravity(context: Context, tabCount: Int): Int {
        return if (shouldUseScrollableTabs(context, tabCount)) {
            com.google.android.material.tabs.TabLayout.GRAVITY_CENTER
        } else {
            com.google.android.material.tabs.TabLayout.GRAVITY_FILL
        }
    }
    
    /**
     * Get responsive dimension in pixels
     */
    fun getResponsiveDimensionPx(context: Context, baseDp: Int): Int {
        val screenInfo = getScreenInfo(context)
        return (baseDp * context.resources.displayMetrics.density * screenInfo.scaleFactor).toInt()
    }
    
    /**
     * Get responsive dimension in DP
     */
    fun getResponsiveDimensionDp(context: Context, baseDp: Int): Int {
        val screenInfo = getScreenInfo(context)
        return (baseDp * screenInfo.scaleFactor).toInt()
    }
    
    /**
     * Log screen information for debugging
     */
    fun logScreenInfo(context: Context) {
        val screenInfo = getScreenInfo(context)
        Log.d(TAG, """
            Screen Info:
            - Size: ${screenInfo.size}
            - Density: ${screenInfo.density}
            - Width: ${screenInfo.widthDp}dp (${screenInfo.widthPx}px)
            - Height: ${screenInfo.heightDp}dp (${screenInfo.heightPx}px)
            - Auto Scale Factor: ${screenInfo.scaleFactor}
        """.trimIndent())
    }
    
    /**
     * Check if current device is in landscape mode
     */
    fun isLandscape(context: Context): Boolean {
        return context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    }
    
    /**
     * Check if current device is a tablet
     */
    fun isTablet(context: Context): Boolean {
        val screenInfo = getScreenInfo(context)
        return screenInfo.size == ScreenSize.XLARGE || 
               (screenInfo.widthDp >= 600 && screenInfo.heightDp >= 600)
    }
    
    /**
     * Apply comprehensive responsive design to a ViewGroup
     */
    fun applyResponsiveDesign(viewGroup: ViewGroup) {
        try {
            val context = viewGroup.context
            
            // Apply responsive scaling to all child views - NO RECURSION to prevent crashes
            for (i in 0 until viewGroup.childCount) {
                val child = viewGroup.getChildAt(i)
                
                when (child) {
                    is TextView -> {
                        // Scale text size responsively using density instead of scaledDensity
                        val currentTextSize = child.textSize / context.resources.displayMetrics.density
                        if (currentTextSize > 0 && currentTextSize < 100) { // Safety bounds
                            applyResponsiveTextSize(child, currentTextSize)
                        }
                    }
                    // Removed recursive ViewGroup processing to prevent infinite loops
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error applying responsive design", e)
        }
    }
}