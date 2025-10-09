package com.stash.opusplayer.ui.appearance

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import androidx.preference.PreferenceManager
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

/**
 * Comprehensive Visual Customization Manager
 * Handles background customization, themes, and visual effects
 */
class VisualCustomizationManager(private val context: Context) {
    
    companion object {
        // Background Type Constants
        const val BACKGROUND_TYPE_COLOR = "color"
        const val BACKGROUND_TYPE_GRADIENT = "gradient"
        const val BACKGROUND_TYPE_PHOTO = "photo"
        
        // Preference Keys
        const val PREF_BACKGROUND_TYPE = "background_type"
        const val PREF_BACKGROUND_COLOR = "background_color"
        const val PREF_GRADIENT_START_COLOR = "gradient_start_color"
        const val PREF_GRADIENT_END_COLOR = "gradient_end_color"
        const val PREF_GRADIENT_ORIENTATION = "gradient_orientation"
        const val PREF_BACKGROUND_PHOTO_PATH = "background_photo_path"
        
        // Photo Background Customization
        const val PREF_PHOTO_BLUR_RADIUS = "photo_blur_radius"
        const val PREF_PHOTO_DIMMING = "photo_dimming"
        const val PREF_PHOTO_OPACITY = "photo_opacity"
        const val PREF_PHOTO_SCALE_TYPE = "photo_scale_type"
        const val PREF_PHOTO_TINT_COLOR = "photo_tint_color"
        const val PREF_PHOTO_TINT_INTENSITY = "photo_tint_intensity"
        
        // Animation Effects
        const val PREF_BACKGROUND_PARALLAX = "background_parallax_enabled"
        const val PREF_BACKGROUND_BREATHING = "background_breathing_enabled"
        const val PREF_COLOR_SHIFT_ENABLED = "color_shift_enabled"
        
        // Visual Effects
        const val PREF_EDGE_GLOW = "edge_glow_enabled"
        const val PREF_SHADOW_EFFECTS = "shadow_effects_enabled"
        const val PREF_BLUR_BEHIND_CONTENT = "blur_behind_content"
        
        // Scale Types for Photo Backgrounds
        const val SCALE_TYPE_CENTER_CROP = "center_crop"
        const val SCALE_TYPE_CENTER_INSIDE = "center_inside"
        const val SCALE_TYPE_FIT_XY = "fit_xy"
        const val SCALE_TYPE_MATRIX = "matrix"
        
        // Gradient Orientations
        const val GRADIENT_VERTICAL = "vertical"
        const val GRADIENT_HORIZONTAL = "horizontal"
        const val GRADIENT_DIAGONAL = "diagonal"
        const val GRADIENT_RADIAL = "radial"
        
        // Default Values
        const val DEFAULT_BLUR_RADIUS = 15
        const val DEFAULT_DIMMING = 30
        const val DEFAULT_OPACITY = 85
        const val DEFAULT_TINT_INTENSITY = 20
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    private val backgroundsDir = File(context.filesDir, "backgrounds")
    
    init {
        // Ensure backgrounds directory exists
        if (!backgroundsDir.exists()) {
            backgroundsDir.mkdirs()
        }
    }
    
    /**
     * Main method to get the current background drawable
     */
    fun getCurrentBackground(): Drawable {
        return when (getBackgroundType()) {
            BACKGROUND_TYPE_COLOR -> createColorBackground()
            BACKGROUND_TYPE_GRADIENT -> createGradientBackground()
            BACKGROUND_TYPE_PHOTO -> createPhotoBackground()
            else -> createDefaultBackground()
        }
    }
    
    /**
     * Get current background type
     */
    fun getBackgroundType(): String {
        return prefs.getString(PREF_BACKGROUND_TYPE, BACKGROUND_TYPE_GRADIENT) ?: BACKGROUND_TYPE_GRADIENT
    }
    
    /**
     * Set background type
     */
    fun setBackgroundType(type: String) {
        prefs.edit().putString(PREF_BACKGROUND_TYPE, type).apply()
    }
    
    /**
     * Create solid color background
     */
    private fun createColorBackground(): Drawable {
        val color = prefs.getInt(PREF_BACKGROUND_COLOR, Color.parseColor("#1a1a1a"))
        return ColorDrawable(color)
    }
    
    /**
     * Create gradient background
     */
    private fun createGradientBackground(): Drawable {
        val startColor = prefs.getInt(PREF_GRADIENT_START_COLOR, Color.parseColor("#2E1065"))
        val endColor = prefs.getInt(PREF_GRADIENT_END_COLOR, Color.parseColor("#0F0F23"))
        val orientation = prefs.getString(PREF_GRADIENT_ORIENTATION, GRADIENT_VERTICAL)
        
        val gradientOrientation = when (orientation) {
            GRADIENT_HORIZONTAL -> GradientDrawable.Orientation.LEFT_RIGHT
            GRADIENT_DIAGONAL -> GradientDrawable.Orientation.TL_BR
            else -> GradientDrawable.Orientation.TOP_BOTTOM
        }
        
        return GradientDrawable(gradientOrientation, intArrayOf(startColor, endColor))
    }
    
    /**
     * Create photo background with all customizations applied
     */
    private fun createPhotoBackground(): Drawable {
        val photoPath = prefs.getString(PREF_BACKGROUND_PHOTO_PATH, null)
        
        if (photoPath == null || !File(photoPath).exists()) {
            return createDefaultBackground()
        }
        
        try {
            var bitmap = BitmapFactory.decodeFile(photoPath)
            if (bitmap == null) return createDefaultBackground()
            
            // Apply blur effect
            val blurRadius = prefs.getInt(PREF_PHOTO_BLUR_RADIUS, DEFAULT_BLUR_RADIUS)
            if (blurRadius > 0) {
                bitmap = applyBlurEffect(bitmap, blurRadius.toFloat())
            }
            
            // Apply dimming
            val dimmingPercent = prefs.getInt(PREF_PHOTO_DIMMING, DEFAULT_DIMMING)
            if (dimmingPercent > 0) {
                bitmap = applyDimming(bitmap, dimmingPercent)
            }
            
            // Apply tint
            val tintColor = prefs.getInt(PREF_PHOTO_TINT_COLOR, Color.TRANSPARENT)
            val tintIntensity = prefs.getInt(PREF_PHOTO_TINT_INTENSITY, DEFAULT_TINT_INTENSITY)
            if (tintColor != Color.TRANSPARENT && tintIntensity > 0) {
                bitmap = applyTint(bitmap, tintColor, tintIntensity)
            }
            
            val drawable = BitmapDrawable(context.resources, bitmap)
            
            // Apply opacity
            val opacity = prefs.getInt(PREF_PHOTO_OPACITY, DEFAULT_OPACITY)
            drawable.alpha = (opacity * 255 / 100).coerceIn(0, 255)
            
            return drawable
            
        } catch (e: Exception) {
            e.printStackTrace()
            return createDefaultBackground()
        }
    }
    
    /**
     * Apply blur effect to bitmap
     */
    private fun applyBlurEffect(bitmap: Bitmap, radius: Float): Bitmap {
        return try {
            // RenderScript is deprecated, use safer alternatives
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                // Use stack blur for Android 12+ (RenderScript deprecated)
                applyStackBlur(bitmap, radius.toInt())
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.JELLY_BEAN_MR1) {
                // Use RenderScript for older versions with proper error handling
                try {
                    applyRenderScriptBlur(bitmap, radius)
                } catch (e: Exception) {
                    // Fallback to stack blur if RenderScript fails
                    applyStackBlur(bitmap, radius.toInt())
                }
            } else {
                applyStackBlur(bitmap, radius.toInt())
            }
        } catch (e: Exception) {
            bitmap
        }
    }
    
    @androidx.annotation.RequiresApi(android.os.Build.VERSION_CODES.JELLY_BEAN_MR1)
    @Suppress("DEPRECATION") // RenderScript is deprecated but still needed for Android < 12
    private fun applyRenderScriptBlur(bitmap: Bitmap, radius: Float): Bitmap {
        var renderScript: android.renderscript.RenderScript? = null
        var blurScript: android.renderscript.ScriptIntrinsicBlur? = null
        var inputAllocation: android.renderscript.Allocation? = null
        var outputAllocation: android.renderscript.Allocation? = null
        
        return try {
            val outputBitmap = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            
            renderScript = android.renderscript.RenderScript.create(context)
            blurScript = android.renderscript.ScriptIntrinsicBlur.create(renderScript, android.renderscript.Element.U8_4(renderScript))
            
            inputAllocation = android.renderscript.Allocation.createFromBitmap(renderScript, bitmap)
            outputAllocation = android.renderscript.Allocation.createFromBitmap(renderScript, outputBitmap)
            
            blurScript.setRadius(radius.coerceIn(0f, 25f))
            blurScript.setInput(inputAllocation)
            blurScript.forEach(outputAllocation)
            
            outputAllocation.copyTo(outputBitmap)
            
            outputBitmap
        } catch (e: Exception) {
            // If RenderScript fails, fallback to stack blur
            applyStackBlur(bitmap, radius.toInt())
        } finally {
            // Cleanup resources to prevent memory leaks
            try {
                inputAllocation?.destroy()
                outputAllocation?.destroy()
                blurScript?.destroy()
                renderScript?.destroy()
            } catch (e: Exception) {
                // Ignore cleanup errors
            }
        }
    }
    
    /**
     * Apply stack blur as fallback for older Android versions
     */
    private fun applyStackBlur(bitmap: Bitmap, radius: Int): Bitmap {
        // Simple implementation of stack blur
        val result = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        
        if (radius < 1) return result
        
        val w = result.width
        val h = result.height
        
        val pix = IntArray(w * h)
        result.getPixels(pix, 0, w, 0, 0, w, h)
        
        val wm = w - 1
        val hm = h - 1
        val wh = w * h
        val div = radius + radius + 1
        
        val r = IntArray(wh)
        val g = IntArray(wh)
        val b = IntArray(wh)
        
        // Extract RGB values
        for (i in 0 until wh) {
            r[i] = (pix[i] and 0xff0000) shr 16
            g[i] = (pix[i] and 0x00ff00) shr 8
            b[i] = pix[i] and 0x0000ff
        }
        
        // Apply horizontal blur
        for (y in 0 until h) {
            val yi = y * w
            for (x in 0 until w) {
                var rsum = 0
                var gsum = 0
                var bsum = 0
                
                for (i in -radius..radius) {
                    val p = yi + ((x + i).coerceIn(0, wm))
                    rsum += r[p]
                    gsum += g[p]
                    bsum += b[p]
                }
                
                r[yi + x] = rsum / div
                g[yi + x] = gsum / div
                b[yi + x] = bsum / div
            }
        }
        
        // Apply vertical blur
        for (x in 0 until w) {
            for (y in 0 until h) {
                var rsum = 0
                var gsum = 0
                var bsum = 0
                
                for (i in -radius..radius) {
                    val p = ((y + i).coerceIn(0, hm)) * w + x
                    rsum += r[p]
                    gsum += g[p]
                    bsum += b[p]
                }
                
                val yi = y * w + x
                pix[yi] = Color.argb(255, rsum / div, gsum / div, bsum / div)
            }
        }
        
        result.setPixels(pix, 0, w, 0, 0, w, h)
        return result
    }
    
    /**
     * Apply dimming to bitmap
     */
    private fun applyDimming(bitmap: Bitmap, dimmingPercent: Int): Bitmap {
        val result = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = android.graphics.Canvas(result)
        
        val overlayPaint = android.graphics.Paint().apply {
            color = Color.BLACK
            alpha = (dimmingPercent * 255 / 100).coerceIn(0, 255)
        }
        
        canvas.drawRect(0f, 0f, result.width.toFloat(), result.height.toFloat(), overlayPaint)
        
        return result
    }
    
    /**
     * Apply color tint to bitmap
     */
    private fun applyTint(bitmap: Bitmap, tintColor: Int, intensity: Int): Bitmap {
        val result = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = android.graphics.Canvas(result)
        
        val tintPaint = android.graphics.Paint().apply {
            color = tintColor
            alpha = (intensity * 255 / 100).coerceIn(0, 255)
            xfermode = android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.OVERLAY)
        }
        
        canvas.drawRect(0f, 0f, result.width.toFloat(), result.height.toFloat(), tintPaint)
        
        return result
    }
    
    /**
     * Create default background
     */
    private fun createDefaultBackground(): Drawable {
        return GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.parseColor("#2E1065"), Color.parseColor("#0F0F23"))
        )
    }
    
    /**
     * Save photo background from URI
     */
    suspend fun setPhotoBackground(uri: Uri): Boolean = withContext(Dispatchers.IO) {
        try {
            val inputStream: InputStream? = context.contentResolver.openInputStream(uri)
            if (inputStream != null) {
                val bitmap = BitmapFactory.decodeStream(inputStream)
                inputStream.close()
                
                if (bitmap != null) {
                    val file = File(backgroundsDir, "background_${System.currentTimeMillis()}.jpg")
                    val outputStream = FileOutputStream(file)
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, outputStream)
                    outputStream.close()
                    
                    prefs.edit()
                        .putString(PREF_BACKGROUND_PHOTO_PATH, file.absolutePath)
                        .putString(PREF_BACKGROUND_TYPE, BACKGROUND_TYPE_PHOTO)
                        .apply()
                    
                    return@withContext true
                }
            }
            false
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
    
    /**
     * Set solid color background
     */
    fun setColorBackground(color: Int) {
        prefs.edit()
            .putInt(PREF_BACKGROUND_COLOR, color)
            .putString(PREF_BACKGROUND_TYPE, BACKGROUND_TYPE_COLOR)
            .apply()
    }
    
    /**
     * Set gradient background
     */
    fun setGradientBackground(startColor: Int, endColor: Int, orientation: String = GRADIENT_VERTICAL) {
        prefs.edit()
            .putInt(PREF_GRADIENT_START_COLOR, startColor)
            .putInt(PREF_GRADIENT_END_COLOR, endColor)
            .putString(PREF_GRADIENT_ORIENTATION, orientation)
            .putString(PREF_BACKGROUND_TYPE, BACKGROUND_TYPE_GRADIENT)
            .apply()
    }
    
    /**
     * Update photo background settings
     */
    fun updatePhotoSettings(
        blurRadius: Int = DEFAULT_BLUR_RADIUS,
        dimming: Int = DEFAULT_DIMMING,
        opacity: Int = DEFAULT_OPACITY,
        tintColor: Int = Color.TRANSPARENT,
        tintIntensity: Int = DEFAULT_TINT_INTENSITY
    ) {
        prefs.edit()
            .putInt(PREF_PHOTO_BLUR_RADIUS, blurRadius)
            .putInt(PREF_PHOTO_DIMMING, dimming)
            .putInt(PREF_PHOTO_OPACITY, opacity)
            .putInt(PREF_PHOTO_TINT_COLOR, tintColor)
            .putInt(PREF_PHOTO_TINT_INTENSITY, tintIntensity)
            .apply()
    }
    
    /**
     * Get photo blur radius
     */
    fun getPhotoBlurRadius(): Int = prefs.getInt(PREF_PHOTO_BLUR_RADIUS, DEFAULT_BLUR_RADIUS)
    
    /**
     * Get photo dimming
     */
    fun getPhotoDimming(): Int = prefs.getInt(PREF_PHOTO_DIMMING, DEFAULT_DIMMING)
    
    /**
     * Get photo opacity
     */
    fun getPhotoOpacity(): Int = prefs.getInt(PREF_PHOTO_OPACITY, DEFAULT_OPACITY)
    
    /**
     * Get photo tint intensity
     */
    fun getPhotoTintIntensity(): Int = prefs.getInt(PREF_PHOTO_TINT_INTENSITY, DEFAULT_TINT_INTENSITY)
    
    /**
     * Check if background effects are enabled
     */
    fun isParallaxEnabled(): Boolean = prefs.getBoolean(PREF_BACKGROUND_PARALLAX, true)
    fun isBreathingEnabled(): Boolean = prefs.getBoolean(PREF_BACKGROUND_BREATHING, false)
    fun isColorShiftEnabled(): Boolean = prefs.getBoolean(PREF_COLOR_SHIFT_ENABLED, true)
    
    /**
     * Set animation preferences
     */
    fun setParallaxEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_BACKGROUND_PARALLAX, enabled).apply()
    }
    
    fun setBreathingEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_BACKGROUND_BREATHING, enabled).apply()
    }
    
    fun setColorShiftEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(PREF_COLOR_SHIFT_ENABLED, enabled).apply()
    }
    
    /**
     * Clear current photo background
     */
    fun clearPhotoBackground() {
        val currentPath = prefs.getString(PREF_BACKGROUND_PHOTO_PATH, null)
        if (currentPath != null) {
            File(currentPath).delete()
        }
        
        prefs.edit()
            .remove(PREF_BACKGROUND_PHOTO_PATH)
            .putString(PREF_BACKGROUND_TYPE, BACKGROUND_TYPE_GRADIENT)
            .apply()
    }
}
