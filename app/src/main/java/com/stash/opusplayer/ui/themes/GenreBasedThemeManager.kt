package com.stash.opusplayer.ui.themes

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import androidx.core.content.ContextCompat
import com.stash.opusplayer.data.Song
import kotlin.math.*
import kotlin.random.Random
import android.animation.AnimatorSet
import android.view.View
import android.view.animation.LinearInterpolator
import android.view.animation.AccelerateDecelerateInterpolator

/**
 * Manager for genre-based dynamic background themes
 * Changes visual themes based on the current music genre
 */
class GenreBasedThemeManager(private val context: Context) {
    
    companion object {
        private const val ANIMATION_DURATION = 3000L
        private const val ROCK_LIGHTNING_COUNT = 8
        private const val CLASSICAL_CURVE_SEGMENTS = 50
        private const val ELECTRONIC_GRID_SIZE = 20
        private const val JAZZ_PARTICLE_COUNT = 30
    }
    
    private var currentTheme: GenreTheme = GenreTheme.DEFAULT
    private var backgroundAnimator: ValueAnimator? = null
    private var themeDrawable: DynamicGenreDrawable? = null
    
    enum class GenreTheme(val keywords: List<String>, val colors: IntArray) {
        ROCK(
            keywords = listOf("rock", "metal", "punk", "hard", "heavy", "alternative"),
            colors = intArrayOf(
                Color.parseColor("#FF4444"),
                Color.parseColor("#FF6B35"),
                Color.parseColor("#AA2200"),
                Color.parseColor("#FFAA00")
            )
        ),
        CLASSICAL(
            keywords = listOf("classical", "symphony", "orchestra", "piano", "violin", "opera"),
            colors = intArrayOf(
                Color.parseColor("#E6E6FA"),
                Color.parseColor("#DDA0DD"),
                Color.parseColor("#9370DB"),
                Color.parseColor("#8A2BE2")
            )
        ),
        ELECTRONIC(
            keywords = listOf("electronic", "edm", "techno", "house", "trance", "dubstep", "synthwave"),
            colors = intArrayOf(
                Color.parseColor("#00FFFF"),
                Color.parseColor("#FF00FF"),
                Color.parseColor("#00FF00"),
                Color.parseColor("#FFFF00")
            )
        ),
        JAZZ(
            keywords = listOf("jazz", "blues", "swing", "bebop", "smooth", "fusion"),
            colors = intArrayOf(
                Color.parseColor("#FFD700"),
                Color.parseColor("#FFA500"),
                Color.parseColor("#FF8C00"),
                Color.parseColor("#B8860B")
            )
        ),
        POP(
            keywords = listOf("pop", "dance", "disco", "funk", "r&b", "soul"),
            colors = intArrayOf(
                Color.parseColor("#FF69B4"),
                Color.parseColor("#DA70D6"),
                Color.parseColor("#BA55D3"),
                Color.parseColor("#9932CC")
            )
        ),
        AMBIENT(
            keywords = listOf("ambient", "chill", "lounge", "new age", "meditation", "relaxing"),
            colors = intArrayOf(
                Color.parseColor("#87CEEB"),
                Color.parseColor("#87CEFA"),
                Color.parseColor("#ADD8E6"),
                Color.parseColor("#B0E0E6")
            )
        ),
        DEFAULT(
            keywords = emptyList(),
            colors = intArrayOf(
                Color.parseColor("#4A5568"),
                Color.parseColor("#2D3748"),
                Color.parseColor("#1A202C"),
                Color.parseColor("#171923")
            )
        )
    }
    
    /**
     * Analyze song genre and apply appropriate theme
     */
    fun applyThemeForSong(song: Song, targetView: View) {
        val detectedTheme = detectGenre(song)
        
        if (detectedTheme != currentTheme) {
            currentTheme = detectedTheme
            transitionToTheme(detectedTheme, targetView)
        }
    }
    
    /**
     * Get current theme drawable for background
     */
    fun getCurrentThemeDrawable(width: Int, height: Int): Drawable? {
        return themeDrawable?.apply {
            setBounds(0, 0, width, height)
        }
    }
    
    private fun detectGenre(song: Song): GenreTheme {
        val searchText = "${song.title} ${song.artistName} ${song.albumName} ${song.genre}".lowercase()
        
        return GenreTheme.values()
            .filter { it != GenreTheme.DEFAULT }
            .maxByOrNull { theme ->
                theme.keywords.count { keyword ->
                    searchText.contains(keyword)
                }
            } ?: GenreTheme.DEFAULT
    }
    
    private fun transitionToTheme(theme: GenreTheme, targetView: View) {
        backgroundAnimator?.cancel()
        
        themeDrawable = DynamicGenreDrawable(theme, targetView.width, targetView.height)
        targetView.background = themeDrawable
        
        // Start theme-specific animations
        when (theme) {
            GenreTheme.ROCK -> animateRockTheme()
            GenreTheme.CLASSICAL -> animateClassicalTheme()
            GenreTheme.ELECTRONIC -> animateElectronicTheme()
            GenreTheme.JAZZ -> animateJazzTheme()
            GenreTheme.POP -> animatePopTheme()
            GenreTheme.AMBIENT -> animateAmbientTheme()
            GenreTheme.DEFAULT -> animateDefaultTheme()
        }
    }
    
    private fun animateRockTheme() {
        backgroundAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ANIMATION_DURATION
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                themeDrawable?.updateRockAnimation(progress)
            }
        }
        backgroundAnimator?.start()
    }
    
    private fun animateClassicalTheme() {
        backgroundAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ANIMATION_DURATION * 2 // Slower for classical
            repeatCount = ValueAnimator.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
            
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                themeDrawable?.updateClassicalAnimation(progress)
            }
        }
        backgroundAnimator?.start()
    }
    
    private fun animateElectronicTheme() {
        backgroundAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ANIMATION_DURATION / 2 // Faster for electronic
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                themeDrawable?.updateElectronicAnimation(progress)
            }
        }
        backgroundAnimator?.start()
    }
    
    private fun animateJazzTheme() {
        backgroundAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ANIMATION_DURATION
            repeatCount = ValueAnimator.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
            
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                themeDrawable?.updateJazzAnimation(progress)
            }
        }
        backgroundAnimator?.start()
    }
    
    private fun animatePopTheme() {
        backgroundAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ANIMATION_DURATION
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                themeDrawable?.updatePopAnimation(progress)
            }
        }
        backgroundAnimator?.start()
    }
    
    private fun animateAmbientTheme() {
        backgroundAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ANIMATION_DURATION * 3 // Very slow for ambient
            repeatCount = ValueAnimator.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
            
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                themeDrawable?.updateAmbientAnimation(progress)
            }
        }
        backgroundAnimator?.start()
    }
    
    private fun animateDefaultTheme() {
        backgroundAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ANIMATION_DURATION * 2
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float
                themeDrawable?.updateDefaultAnimation(progress)
            }
        }
        backgroundAnimator?.start()
    }
    
    fun release() {
        backgroundAnimator?.cancel()
        backgroundAnimator = null
        themeDrawable = null
    }
    
    /**
     * Custom drawable that renders genre-specific animated backgrounds
     */
    private class DynamicGenreDrawable(
        private val theme: GenreTheme,
        private val width: Int,
        private val height: Int
    ) : Drawable() {
        
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val path = Path()
        private var animationProgress = 0f
        
        // Rock theme - lightning bolts
        private val lightningPaths = Array(ROCK_LIGHTNING_COUNT) { Path() }
        
        // Classical theme - flowing curves
        private val curvePaths = Array(3) { Path() }
        
        // Electronic theme - geometric grid
        private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f
        }
        
        // Jazz theme - floating particles
        private data class Particle(var x: Float, var y: Float, var size: Float, var alpha: Float, var velocity: Float)
        private val particles = Array(JAZZ_PARTICLE_COUNT) { 
            Particle(
                Random.nextFloat() * width,
                Random.nextFloat() * height,
                Random.nextFloat() * 20f + 5f,
                Random.nextFloat(),
                Random.nextFloat() * 2f + 0.5f
            )
        }
        
        override fun draw(canvas: Canvas) {
            when (theme) {
                GenreTheme.ROCK -> drawRockTheme(canvas)
                GenreTheme.CLASSICAL -> drawClassicalTheme(canvas)
                GenreTheme.ELECTRONIC -> drawElectronicTheme(canvas)
                GenreTheme.JAZZ -> drawJazzTheme(canvas)
                GenreTheme.POP -> drawPopTheme(canvas)
                GenreTheme.AMBIENT -> drawAmbientTheme(canvas)
                GenreTheme.DEFAULT -> drawDefaultTheme(canvas)
            }
        }
        
        private fun drawRockTheme(canvas: Canvas) {
            // Dark gradient background
            paint.shader = LinearGradient(
                0f, 0f, 0f, height.toFloat(),
                theme.colors[2], theme.colors[3],
                Shader.TileMode.CLAMP
            )
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
            
            // Lightning bolts
            paint.shader = null
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 4f
            paint.color = theme.colors[0]
            paint.alpha = (128 + 127 * sin(animationProgress * PI * 4)).toInt()
            
            lightningPaths.forEachIndexed { index, path ->
                if (Random.nextFloat() < 0.1f) { // Randomly regenerate lightning
                    generateLightning(path, index)
                }
                canvas.drawPath(path, paint)
            }
        }
        
        private fun drawClassicalTheme(canvas: Canvas) {
            // Soft gradient background
            paint.shader = LinearGradient(
                0f, 0f, width.toFloat(), height.toFloat(),
                theme.colors[0], theme.colors[3],
                Shader.TileMode.CLAMP
            )
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
            
            // Flowing curves
            paint.shader = null
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 3f
            paint.color = theme.colors[2]
            paint.alpha = (100 + 55 * sin(animationProgress * PI)).toInt()
            
            curvePaths.forEachIndexed { index, path ->
                generateCurve(path, index)
                canvas.drawPath(path, paint)
            }
        }
        
        private fun drawElectronicTheme(canvas: Canvas) {
            // Dark background
            canvas.drawColor(Color.BLACK)
            
            // Neon grid
            gridPaint.color = theme.colors[0]
            gridPaint.alpha = (150 + 105 * sin(animationProgress * PI * 2)).toInt()
            
            val spacing = width / ELECTRONIC_GRID_SIZE.toFloat()
            
            // Vertical lines
            for (i in 0..ELECTRONIC_GRID_SIZE) {
                val x = i * spacing
                canvas.drawLine(x, 0f, x, height.toFloat(), gridPaint)
            }
            
            // Horizontal lines
            for (i in 0..ELECTRONIC_GRID_SIZE) {
                val y = i * spacing
                canvas.drawLine(0f, y, width.toFloat(), y, gridPaint)
            }
            
            // Pulsing nodes at intersections
            paint.style = Paint.Style.FILL
            paint.color = theme.colors[1]
            val pulseRadius = 8f + 4f * sin(animationProgress * PI * 3).toFloat()
            
            for (i in 0..ELECTRONIC_GRID_SIZE step 4) {
                for (j in 0..ELECTRONIC_GRID_SIZE step 4) {
                    val x = i * spacing
                    val y = j * spacing
                    canvas.drawCircle(x, y, pulseRadius, paint)
                }
            }
        }
        
        private fun drawJazzTheme(canvas: Canvas) {
            // Warm gradient background
            paint.shader = RadialGradient(
                width / 2f, height / 2f, max(width, height) / 2f,
                theme.colors[0], theme.colors[3],
                Shader.TileMode.CLAMP
            )
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
            
            // Floating particles
            paint.shader = null
            paint.style = Paint.Style.FILL
            
            particles.forEach { particle ->
                paint.color = theme.colors[1]
                paint.alpha = (particle.alpha * 255).toInt()
                canvas.drawCircle(particle.x, particle.y, particle.size, paint)
                
                // Update particle position
                particle.y -= particle.velocity
                if (particle.y < -particle.size) {
                    particle.y = height + particle.size
                    particle.x = Random.nextFloat() * width
                }
            }
        }
        
        private fun drawPopTheme(canvas: Canvas) {
            // Bright gradient background with animated colors
            val color1 = blendColors(theme.colors[0], theme.colors[1], ((sin(animationProgress * PI) + 1) / 2).toFloat())
            val color2 = blendColors(theme.colors[2], theme.colors[3], ((cos(animationProgress * PI) + 1) / 2).toFloat())
            
            paint.shader = LinearGradient(
                0f, 0f, width.toFloat(), height.toFloat(),
                color1, color2,
                Shader.TileMode.CLAMP
            )
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
            
            // Pulsing circles
            paint.shader = null
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 6f
            paint.color = Color.WHITE
            paint.alpha = (100 + 155 * sin(animationProgress * PI * 2)).toInt()
            
            val radius = (width / 4f) * (1f + 0.3f * sin(animationProgress * PI * 3).toFloat())
            canvas.drawCircle(width / 2f, height / 2f, radius, paint)
        }
        
        private fun drawAmbientTheme(canvas: Canvas) {
            // Soft, slowly changing background
            val progress = ((sin(animationProgress * PI) + 1) / 2).toFloat()
            val color = blendColors(theme.colors[0], theme.colors[3], progress)
            
            canvas.drawColor(color)
            
            // Gentle waves
            paint.color = theme.colors[2]
            paint.alpha = (80 + 40 * sin(animationProgress * PI)).toInt()
            paint.style = Paint.Style.FILL
            
            path.reset()
            path.moveTo(0f, height / 2f)
            
            for (x in 0..width step 10) {
                val waveHeight = 50f * sin((x / 100f) + animationProgress * PI).toFloat()
                path.lineTo(x.toFloat(), height / 2f + waveHeight)
            }
            
            path.lineTo(width.toFloat(), height.toFloat())
            path.lineTo(0f, height.toFloat())
            path.close()
            
            canvas.drawPath(path, paint)
        }
        
        private fun drawDefaultTheme(canvas: Canvas) {
            // Simple gradient
            paint.shader = LinearGradient(
                0f, 0f, 0f, height.toFloat(),
                theme.colors[0], theme.colors[3],
                Shader.TileMode.CLAMP
            )
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        }
        
        private fun generateLightning(path: Path, index: Int) {
            path.reset()
            val startX = Random.nextFloat() * width
            val startY = Random.nextFloat() * height * 0.3f
            val endX = Random.nextFloat() * width
            val endY = height - Random.nextFloat() * height * 0.3f
            
            path.moveTo(startX, startY)
            
            val segments = 6
            for (i in 1..segments) {
                val progress = i.toFloat() / segments
                val x = startX + (endX - startX) * progress + (Random.nextFloat() - 0.5f) * 80f
                val y = startY + (endY - startY) * progress + (Random.nextFloat() - 0.5f) * 40f
                path.lineTo(x, y)
            }
        }
        
        private fun generateCurve(path: Path, index: Int) {
            path.reset()
            val amplitude = height / 8f
            val frequency = 2f + index * 0.5f
            val offset = animationProgress * PI * 0.5f
            
            path.moveTo(0f, height / 2f)
            
            for (segment in 0..CLASSICAL_CURVE_SEGMENTS) {
                val x = (segment.toFloat() / CLASSICAL_CURVE_SEGMENTS) * width
                val y = height / 2f + amplitude * sin(frequency * (x / width) * PI * 2 + offset).toFloat()
                path.lineTo(x, y)
            }
        }
        
        private fun blendColors(color1: Int, color2: Int, ratio: Float): Int {
            val inverseRatio = 1f - ratio
            
            val r = (Color.red(color1) * inverseRatio + Color.red(color2) * ratio).toInt()
            val g = (Color.green(color1) * inverseRatio + Color.green(color2) * ratio).toInt()
            val b = (Color.blue(color1) * inverseRatio + Color.blue(color2) * ratio).toInt()
            val a = (Color.alpha(color1) * inverseRatio + Color.alpha(color2) * ratio).toInt()
            
            return Color.argb(a, r, g, b)
        }
        
        fun updateRockAnimation(progress: Float) {
            animationProgress = progress
            invalidateSelf()
        }
        
        fun updateClassicalAnimation(progress: Float) {
            animationProgress = progress
            invalidateSelf()
        }
        
        fun updateElectronicAnimation(progress: Float) {
            animationProgress = progress
            invalidateSelf()
        }
        
        fun updateJazzAnimation(progress: Float) {
            animationProgress = progress
            invalidateSelf()
        }
        
        fun updatePopAnimation(progress: Float) {
            animationProgress = progress
            invalidateSelf()
        }
        
        fun updateAmbientAnimation(progress: Float) {
            animationProgress = progress
            invalidateSelf()
        }
        
        fun updateDefaultAnimation(progress: Float) {
            animationProgress = progress
            invalidateSelf()
        }
        
        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }
        
        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }
        
        override fun getOpacity(): Int {
            return PixelFormat.TRANSLUCENT
        }
    }
}
