package com.stash.opusplayer.ui.visualizer

import android.animation.*
import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.preference.PreferenceManager
import kotlin.math.*
import kotlin.random.Random
import android.media.audiofx.Visualizer
import com.stash.opusplayer.ui.appearance.AppearancePreferences

/**
 * Enhanced SynthWave visualizer with advanced animations and effects
 */
class EnhancedSynthWaveView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private const val TAG = "EnhancedSynthWaveView"
        private const val GRID_LINES = 20
        private const val FREQUENCY_BANDS = 64
        private const val MAX_AMPLITUDE = 255f
        private const val LIGHTNING_DURATION = 200L
        private const val PARTICLE_COUNT = 50
        private const val BREATHING_DURATION = 3000L
        private const val COLOR_SHIFT_DURATION = 5000L
    }

    // Paint objects
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF00FF")
        style = Paint.Style.STROKE
        strokeWidth = 2f
        pathEffect = DashPathEffect(floatArrayOf(10f, 5f), 0f)
    }
    
    private val waveformPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 4f
        shader = LinearGradient(
            0f, 0f, 0f, 500f,
            Color.parseColor("#FF00FF"),
            Color.parseColor("#00FFFF"),
            Shader.TileMode.CLAMP
        )
    }
    
    private val spectrumPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        shader = LinearGradient(
            0f, 0f, 0f, 300f,
            intArrayOf(
                Color.parseColor("#FF00FF"),
                Color.parseColor("#8000FF"),
                Color.parseColor("#0080FF"),
                Color.parseColor("#00FFFF")
            ),
            floatArrayOf(0f, 0.3f, 0.7f, 1f),
            Shader.TileMode.CLAMP
        )
    }
    
    private val lightningPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 6f
        setShadowLayer(10f, 0f, 0f, Color.WHITE)
    }
    
    private val particlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF00FF")
        style = Paint.Style.FILL
    }
    
    private val ripplePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 3f
        color = Color.parseColor("#00FFFF")
    }
    
    // Additional paint objects for different visualizer modes
    private val mountainPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader = LinearGradient(
            0f, 0f, 0f, 400f,
            intArrayOf(
                Color.parseColor("#FF4444"),
                Color.parseColor("#FF8844"),
                Color.parseColor("#44FF44")
            ),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        )
    }
    
    private val oscilloscopePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#00FF00")
        style = Paint.Style.STROKE
        strokeWidth = 3f
        setShadowLayer(8f, 0f, 0f, Color.parseColor("#00FF00"))
    }
    
    private val vuMeterPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        shader = LinearGradient(
            0f, 0f, 200f, 0f,
            intArrayOf(
                Color.parseColor("#00FF00"),
                Color.parseColor("#FFFF00"),
                Color.parseColor("#FF0000")
            ),
            floatArrayOf(0f, 0.7f, 1f),
            Shader.TileMode.CLAMP
        )
    }
    
    private val fractalPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f
        color = Color.parseColor("#FF00FF")
    }

    // Animation data
    private var waveformData: ByteArray? = null
    private var spectrumData: FloatArray? = null
    private var isAnimating = false
    private var animationPhase = 0f
    private var breathingPhase = 0f
    private var colorShiftPhase = 0f
    
    // Lightning effect
    private var lightningActive = false
    private var lightningPath = Path()
    private var lightningAnimator: ValueAnimator? = null
    private var lightningOpacity = 0f
    
    // Particle system
    private val particles = mutableListOf<Particle>()
    private var particleAnimator: ValueAnimator? = null
    
    // Ripple effects
    private val ripples = mutableListOf<Ripple>()
    private var rippleAnimator: ValueAnimator? = null
    
    // Preference manager for settings
    private val prefs = PreferenceManager.getDefaultSharedPreferences(context)
    private var preferenceListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null
    
    // Animation preferences - using correct keys that match SettingsFragment
    private var enableLightning: Boolean
        get() = prefs.getBoolean("synthwave_lightning_enabled", true)
        set(value) = prefs.edit().putBoolean("synthwave_lightning_enabled", value).apply()
    
    private var enableParticles: Boolean
        get() = prefs.getBoolean("synthwave_particles_enabled", true)
        set(value) = prefs.edit().putBoolean("synthwave_particles_enabled", value).apply()
    
    private var enableRipples: Boolean
        get() = prefs.getBoolean("synthwave_ripples_enabled", true)
        set(value) = prefs.edit().putBoolean("synthwave_ripples_enabled", value).apply()
    
    private var enableBreathing: Boolean
        get() = prefs.getBoolean("synthwave_breathing_enabled", true)
        set(value) = prefs.edit().putBoolean("synthwave_breathing_enabled", value).apply()
    
    private var enableColorShift: Boolean
        get() = prefs.getBoolean("synthwave_color_shift_enabled", true)
        set(value) = prefs.edit().putBoolean("synthwave_color_shift_enabled", value).apply()
    
    private var animationIntensity: Float
        get() = prefs.getFloat("synthwave_intensity", 1f)
        set(value) = prefs.edit().putFloat("synthwave_intensity", value).apply()
    
    // Visualizer mode selection
    enum class VisualizerMode {
        SYNTHWAVE,      // Original synthwave style
        FREQUENCY_MOUNTAIN,  // 3D frequency mountains
        PARTICLE_GALAXY,     // Particle constellation
        RETRO_OSCILLOSCOPE,  // Classic green oscilloscope
        VU_METERS,          // Analog VU meters
        FRACTAL_PATTERNS    // Mathematical fractals
    }
    
    private var currentMode: VisualizerMode
        get() = VisualizerMode.valueOf(
            prefs.getString("synthwave_visualizer_mode", VisualizerMode.SYNTHWAVE.name) 
                ?: VisualizerMode.SYNTHWAVE.name
        )
        set(value) = prefs.edit().putString("synthwave_visualizer_mode", value.name).apply()
    
    // Audio visualizer support
    private var visualizer: Visualizer? = null
    private var audioSessionId: Int = 0
    
    // Progress tracking
    private var currentProgress: Float = 0f // 0f to 1f
    private var progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FFFF00")
        style = Paint.Style.STROKE
        strokeWidth = 4f
        setShadowLayer(8f, 0f, 0f, Color.parseColor("#FFFF00"))
    }
    
    // Seek listener
    private var onSeekListener: ((Float) -> Unit)? = null
    
    // Particle galaxy data
    private data class Star(var x: Float, var y: Float, var brightness: Float, var size: Float, var velocity: Float)
    private val galaxyStars = mutableListOf<Star>()
    
    // VU meter data
    private var leftChannelLevel = 0f
    private var rightChannelLevel = 0f
    
    // Fractal data
    private var fractalIterations = 0
    private val fractalPath = Path()

    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
        setupPreferenceListener()
        // Delay animations and particle initialization until view has dimensions
        post {
            if (width > 0 && height > 0) {
                setupAnimations()
                initializeParticles()
                initializeGalaxyStars()
            }
        }
    }
    
    private fun setupPreferenceListener() {
        preferenceListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            when (key) {
                "synthwave_lightning_enabled",
                "synthwave_particles_enabled",
                "synthwave_ripples_enabled",
                "synthwave_breathing_enabled",
                "synthwave_color_shift_enabled",
                "synthwave_intensity" -> {
                    post {
                        // Restart animations with new settings
                        stopAllAnimations()
                        setupAnimations()
                        if (enableParticles) {
                            initializeParticles()
                        }
                        invalidate()
                    }
                }
            }
        }
        prefs.registerOnSharedPreferenceChangeListener(preferenceListener)
    }
    
    private fun stopAllAnimations() {
        particleAnimator?.cancel()
        particleAnimator = null
        rippleAnimator?.cancel() 
        rippleAnimator = null
        lightningAnimator?.cancel()
        lightningAnimator = null
    }
    
    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopAllAnimations()
        releaseVisualizer()
        preferenceListener?.let {
            prefs.unregisterOnSharedPreferenceChangeListener(it)
        }
        preferenceListener = null
    }

    private fun setupAnimations() {
        // Main animation loop
        val mainAnimator = ValueAnimator.ofFloat(0f, 2 * PI.toFloat()).apply {
            duration = 2000
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { animation ->
                animationPhase = animation.animatedValue as Float
                invalidate()
            }
        }
        
        // Breathing animation
        val breathingAnimator = ValueAnimator.ofFloat(0f, 2 * PI.toFloat()).apply {
            duration = BREATHING_DURATION
            repeatCount = ValueAnimator.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                breathingPhase = animation.animatedValue as Float
            }
        }
        
        // Color shift animation
        val colorShiftAnimator = ValueAnimator.ofFloat(0f, 2 * PI.toFloat()).apply {
            duration = COLOR_SHIFT_DURATION
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { animation ->
                colorShiftPhase = animation.animatedValue as Float
                updateShaders()
            }
        }
        
        // Start animations
        if (enableBreathing) breathingAnimator.start()
        if (enableColorShift) colorShiftAnimator.start()
        mainAnimator.start()
    }
    
    private fun initializeParticles() {
        particles.clear()
        if (width <= 0 || height <= 0) return
        
        repeat(PARTICLE_COUNT) {
            particles.add(Particle(
                x = Random.nextFloat() * width,
                y = Random.nextFloat() * height,
                vx = (Random.nextFloat() - 0.5f) * 4f,
                vy = (Random.nextFloat() - 0.5f) * 4f,
                life = Random.nextFloat()
            ))
        }
        
        if (enableParticles) {
            particleAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 100
                repeatCount = ValueAnimator.INFINITE
                addUpdateListener {
                    updateParticles()
                }
            }
            particleAnimator?.start()
        }
    }
    
    private fun initializeGalaxyStars() {
        galaxyStars.clear()
        if (width <= 0 || height <= 0) return
        
        repeat(100) {
            galaxyStars.add(
                Star(
                    x = Random.nextFloat() * width,
                    y = Random.nextFloat() * height,
                    brightness = Random.nextFloat(),
                    size = Random.nextFloat() * 8f + 2f,
                    velocity = Random.nextFloat() * 2f + 0.5f
                )
            )
        }
    }
    
    private fun updateShaders() {
        if (enableColorShift && height > 0) {
            val hueShift = (colorShiftPhase * 180 / PI).toFloat()
            val colors = intArrayOf(
                adjustHue(Color.parseColor("#FF00FF"), hueShift),
                adjustHue(Color.parseColor("#8000FF"), hueShift),
                adjustHue(Color.parseColor("#0080FF"), hueShift),
                adjustHue(Color.parseColor("#00FFFF"), hueShift)
            )
            
            spectrumPaint.shader = LinearGradient(
                0f, 0f, 0f, height.toFloat(),
                colors,
                floatArrayOf(0f, 0.3f, 0.7f, 1f),
                Shader.TileMode.CLAMP
            )
        }
    }
    
    private fun adjustHue(color: Int, hueShift: Float): Int {
        val hsv = FloatArray(3)
        Color.colorToHSV(color, hsv)
        hsv[0] = (hsv[0] + hueShift) % 360f
        return Color.HSVToColor(hsv)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w > 0 && h > 0) {
            updateShaders()
            initializeParticles()
            initializeGalaxyStars()
            // Setup animations if not already running
            if (!isAnimating) {
                setupAnimations()
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        
        // Safety check - don't draw if dimensions are invalid
        if (width <= 0 || height <= 0) {
            return
        }
        
        try {
            // Apply breathing effect
            if (enableBreathing) {
                val scale = 1f + sin(breathingPhase) * 0.05f * animationIntensity
                canvas.scale(scale, scale, width / 2f, height / 2f)
            }
            
            // Draw based on current visualizer mode
            when (currentMode) {
                VisualizerMode.SYNTHWAVE -> drawSynthWaveMode(canvas)
                VisualizerMode.FREQUENCY_MOUNTAIN -> drawFrequencyMountain(canvas)
                VisualizerMode.PARTICLE_GALAXY -> drawParticleGalaxy(canvas)
                VisualizerMode.RETRO_OSCILLOSCOPE -> drawRetroOscilloscope(canvas)
                VisualizerMode.VU_METERS -> drawVUMeters(canvas)
                VisualizerMode.FRACTAL_PATTERNS -> drawFractalPatterns(canvas)
            }
            
            // Draw progress line (common to all modes)
            drawProgressLine(canvas)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error during onDraw", e)
            // Draw a simple fallback to avoid blank screen
            canvas.drawColor(Color.parseColor("#1a1a1a"))
        }
    }
    
    private fun drawSynthWaveMode(canvas: Canvas) {
        // Original synthwave visualization
        drawGrid(canvas)
        drawSpectrum(canvas)
        drawWaveform(canvas)
        
        // Draw effects
        if (enableLightning) drawLightning(canvas)
        if (enableParticles) drawParticles(canvas)
        if (enableRipples) drawRipples(canvas)
    }
    
    private fun drawFrequencyMountain(canvas: Canvas) {
        val spectrum = spectrumData ?: return
        if (width <= 0 || height <= 0) return
        
        canvas.drawColor(Color.BLACK) // Dark background
        
        val barWidth = width.toFloat() / spectrum.size
        val path = Path()
        
        // Create mountain silhouette
        path.moveTo(0f, height.toFloat())
        
        for (i in spectrum.indices) {
            val amplitude = spectrum[i] * animationIntensity
            val barHeight = (amplitude / MAX_AMPLITUDE) * height * 0.8f
            val x = i * barWidth
            val y = height - barHeight
            
            if (i == 0) {
                path.lineTo(x, y)
            } else {
                // Add some curve smoothing
                val prevX = (i - 1) * barWidth
                val controlX = (prevX + x) / 2f
                path.quadTo(controlX, y, x, y)
            }
        }
        
        path.lineTo(width.toFloat(), height.toFloat())
        path.close()
        
        canvas.drawPath(path, mountainPaint)
        
        // Add peaks with glow effect
        for (i in spectrum.indices) {
            val amplitude = spectrum[i] * animationIntensity
            if (amplitude > MAX_AMPLITUDE * 0.6f) {
                val x = i * barWidth
                val y = height - (amplitude / MAX_AMPLITUDE) * height * 0.8f
                
                val glowPaint = Paint(mountainPaint).apply {
                    setShadowLayer(20f, 0f, 0f, Color.WHITE)
                }
                canvas.drawCircle(x, y, 8f, glowPaint)
            }
        }
    }
    
    private fun drawParticleGalaxy(canvas: Canvas) {
        canvas.drawColor(Color.BLACK) // Space background
        
        // Update and draw stars
        val spectrum = spectrumData ?: FloatArray(16) { 0f }
        
        galaxyStars.forEachIndexed { index, star ->
            // Make stars react to audio
            val audioIndex = (index * spectrum.size / galaxyStars.size).coerceIn(0, spectrum.lastIndex)
            val audioInfluence = spectrum[audioIndex] / MAX_AMPLITUDE
            
            star.brightness = (star.brightness * 0.9f + audioInfluence * 0.1f).coerceIn(0f, 1f)
            star.size = star.size + audioInfluence * 3f
            
            // Move stars
            star.x -= star.velocity * animationIntensity
            if (star.x < -star.size) {
                star.x = width + star.size
                star.y = Random.nextFloat() * height
            }
            
            // Draw star with brightness-based alpha
            particlePaint.alpha = (star.brightness * 255).toInt()
            particlePaint.color = Color.HSVToColor(
                floatArrayOf(
                    (index * 360f / galaxyStars.size) % 360f,
                    0.8f,
                    star.brightness
                )
            )
            
            canvas.drawCircle(star.x, star.y, star.size, particlePaint)
            
            // Add connecting lines for constellation effect
            if (index > 0 && star.brightness > 0.5f) {
                val prevStar = galaxyStars[index - 1]
                val distance = sqrt((star.x - prevStar.x).pow(2) + (star.y - prevStar.y).pow(2))
                if (distance < 150f && prevStar.brightness > 0.5f) {
                    val linePaint = Paint(particlePaint).apply {
                        strokeWidth = 2f
                        alpha = ((star.brightness + prevStar.brightness) * 127).toInt()
                    }
                    canvas.drawLine(star.x, star.y, prevStar.x, prevStar.y, linePaint)
                }
            }
        }
    }
    
    private fun drawRetroOscilloscope(canvas: Canvas) {
        canvas.drawColor(Color.parseColor("#001100")) // Dark green background
        
        val waveform = waveformData ?: return
        if (width <= 0 || height <= 0) return
        
        val path = Path()
        val centerY = height / 2f
        val stepX = width.toFloat() / waveform.size
        
        // Draw grid lines (classic oscilloscope look)
        val gridPaint = Paint(oscilloscopePaint).apply {
            alpha = 50
            strokeWidth = 1f
        }
        
        // Horizontal grid lines
        for (i in 0..8) {
            val y = (height / 8f) * i
            canvas.drawLine(0f, y, width.toFloat(), y, gridPaint)
        }
        
        // Vertical grid lines
        for (i in 0..10) {
            val x = (width / 10f) * i
            canvas.drawLine(x, 0f, x, height.toFloat(), gridPaint)
        }
        
        // Draw waveform
        path.moveTo(0f, centerY)
        
        for (i in waveform.indices) {
            val amplitude = (waveform[i].toInt() and 0xFF) - 128
            val normalizedAmplitude = amplitude / 128f * animationIntensity
            val y = centerY + normalizedAmplitude * height * 0.4f
            val x = i * stepX
            
            if (i == 0) {
                path.moveTo(x, y)
            } else {
                path.lineTo(x, y)
            }
        }
        
        canvas.drawPath(path, oscilloscopePaint)
        
        // Add phosphor glow effect
        val glowPaint = Paint(oscilloscopePaint).apply {
            strokeWidth = 8f
            alpha = 100
        }
        canvas.drawPath(path, glowPaint)
    }
    
    private fun drawVUMeters(canvas: Canvas) {
        canvas.drawColor(Color.parseColor("#222222")) // Dark background
        
        val spectrum = spectrumData ?: return
        if (width <= 0 || height <= 0) return
        
        // Calculate stereo levels from spectrum data
        leftChannelLevel = spectrum.take(spectrum.size / 2).maxOrNull() ?: 0f
        rightChannelLevel = spectrum.drop(spectrum.size / 2).maxOrNull() ?: 0f
        
        val meterWidth = width * 0.8f
        val meterHeight = 40f
        val centerY = height / 2f
        
        // Left channel VU meter
        val leftY = centerY - 60f
        drawVUMeter(canvas, width * 0.1f, leftY, meterWidth, meterHeight, leftChannelLevel / MAX_AMPLITUDE, "L")
        
        // Right channel VU meter
        val rightY = centerY + 20f
        drawVUMeter(canvas, width * 0.1f, rightY, meterWidth, meterHeight, rightChannelLevel / MAX_AMPLITUDE, "R")
        
        // Add peak indicators
        drawPeakIndicators(canvas)
    }
    
    private fun drawVUMeter(canvas: Canvas, x: Float, y: Float, width: Float, height: Float, level: Float, label: String) {
        // Background
        val bgPaint = Paint().apply {
            color = Color.parseColor("#444444")
            style = Paint.Style.FILL
        }
        canvas.drawRect(x, y, x + width, y + height, bgPaint)
        
        // Level bar
        val levelWidth = width * level.coerceIn(0f, 1f)
        canvas.drawRect(x, y, x + levelWidth, y + height, vuMeterPaint)
        
        // Scale markings
        val markPaint = Paint().apply {
            color = Color.WHITE
            textSize = 12f
            textAlign = Paint.Align.CENTER
        }
        
        // dB scale markings
        val dbMarks = arrayOf(-20, -10, -6, -3, 0)
        dbMarks.forEach { db ->
            val markX = x + width * ((db + 20f) / 20f)
            canvas.drawLine(markX, y + height, markX, y + height + 10f, markPaint)
            canvas.drawText(db.toString(), markX, y + height + 25f, markPaint)
        }
        
        // Channel label
        val labelPaint = Paint().apply {
            color = Color.WHITE
            textSize = 16f
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(label, x - 20f, y + height / 2f + 6f, labelPaint)
    }
    
    private fun drawPeakIndicators(canvas: Canvas) {
        val spectrum = spectrumData ?: return
        
        // Find peaks in spectrum
        val peakThreshold = MAX_AMPLITUDE * 0.7f
        spectrum.forEachIndexed { index, value ->
            if (value > peakThreshold) {
                val x = (index.toFloat() / spectrum.size) * width
                val y = height * 0.1f
                
                val peakPaint = Paint().apply {
                    color = Color.RED
                    style = Paint.Style.FILL
                }
                
                canvas.drawCircle(x, y, 8f, peakPaint)
            }
        }
    }
    
    private fun drawFractalPatterns(canvas: Canvas) {
        canvas.drawColor(Color.BLACK)
        
        val spectrum = spectrumData ?: return
        if (width <= 0 || height <= 0) return
        
        // Use audio data to influence fractal generation
        val audioEnergy = spectrum.average()
        fractalIterations = (audioEnergy / MAX_AMPLITUDE * 8).toInt().coerceIn(3, 8)
        
        val centerX = width / 2f
        val centerY = height / 2f
        val radius = min(width, height) / 4f * animationIntensity
        
        // Draw fractal tree
        drawFractalBranch(canvas, centerX, centerY + radius / 2f, -90f, radius, fractalIterations)
        
        // Draw fractal spirals based on frequency bands
        spectrum.forEachIndexed { index, amplitude ->
            if (amplitude > MAX_AMPLITUDE * 0.3f) {
                val angle = (index.toFloat() / spectrum.size) * 360f
                val spiralRadius = (amplitude / MAX_AMPLITUDE) * radius * 0.5f
                drawFractalSpiral(canvas, centerX, centerY, angle, spiralRadius)
            }
        }
    }
    
    private fun drawFractalBranch(canvas: Canvas, x: Float, y: Float, angle: Float, length: Float, iterations: Int) {
        if (iterations <= 0 || length < 5f) return
        
        val radians = angle * PI.toFloat() / 180f
        val endX = x + cos(radians) * length
        val endY = y + sin(radians) * length
        
        // Draw branch with color based on iteration depth
        val branchPaint = Paint(fractalPaint).apply {
            color = Color.HSVToColor(
                floatArrayOf(
                    (iterations * 60f) % 360f,
                    0.8f,
                    1f
                )
            )
            strokeWidth = iterations.toFloat()
        }
        
        canvas.drawLine(x, y, endX, endY, branchPaint)
        
        // Recursive branches
        val newLength = length * 0.7f
        drawFractalBranch(canvas, endX, endY, angle - 30f, newLength, iterations - 1)
        drawFractalBranch(canvas, endX, endY, angle + 30f, newLength, iterations - 1)
    }
    
    private fun drawFractalSpiral(canvas: Canvas, centerX: Float, centerY: Float, baseAngle: Float, radius: Float) {
        val path = Path()
        val steps = 50
        
        for (i in 0..steps) {
            val progress = i.toFloat() / steps
            val angle = baseAngle + progress * 720f // 2 full rotations
            val currentRadius = radius * (1f - progress)
            
            val radians = angle * PI.toFloat() / 180f
            val x = centerX + cos(radians) * currentRadius
            val y = centerY + sin(radians) * currentRadius
            
            if (i == 0) {
                path.moveTo(x, y)
            } else {
                path.lineTo(x, y)
            }
        }
        
        val spiralPaint = Paint(fractalPaint).apply {
            color = Color.HSVToColor(
                floatArrayOf(
                    baseAngle % 360f,
                    1f,
                    0.8f
                )
            )
        }
        
        canvas.drawPath(path, spiralPaint)
    }
    
    private fun drawGrid(canvas: Canvas) {
        if (width <= 0 || height <= 0) return
        
        val gridSpacing = width / GRID_LINES.toFloat()
        
        // Vertical grid lines
        for (i in 0..GRID_LINES) {
            val x = i * gridSpacing
            val alpha = (255 * (0.3f + 0.2f * sin(animationPhase + i * 0.1f))).toInt()
            gridPaint.alpha = alpha
            canvas.drawLine(x, 0f, x, height.toFloat(), gridPaint)
        }
        
        // Horizontal grid lines  
        val horizontalSpacing = height / (GRID_LINES / 2f)
        for (i in 0..(GRID_LINES / 2)) {
            val y = i * horizontalSpacing
            val alpha = (255 * (0.3f + 0.2f * sin(animationPhase + i * 0.15f))).toInt()
            gridPaint.alpha = alpha
            canvas.drawLine(0f, y, width.toFloat(), y, gridPaint)
        }
    }
    
    private fun drawSpectrum(canvas: Canvas) {
        val spectrum = spectrumData ?: return
        if (width <= 0 || height <= 0) return
        
        val barWidth = width.toFloat() / spectrum.size
        
        for (i in spectrum.indices) {
            val amplitude = spectrum[i] * animationIntensity
            val barHeight = (amplitude / MAX_AMPLITUDE) * height * 0.6f
            val x = i * barWidth
            val y = height.toFloat()
            
            // Add wave effect
            val waveOffset = sin(animationPhase + i * 0.1f) * 10f * animationIntensity
            
            canvas.drawRect(
                x, 
                y - barHeight + waveOffset, 
                x + barWidth - 2f, 
                y + waveOffset, 
                spectrumPaint
            )
        }
    }
    
    private fun drawWaveform(canvas: Canvas) {
        val waveform = waveformData ?: return
        if (width <= 0 || height <= 0) return
        
        val path = Path()
        val centerY = height / 2f
        val stepX = width.toFloat() / waveform.size
        
        path.moveTo(0f, centerY)
        
        for (i in waveform.indices) {
            val amplitude = (waveform[i].toInt() and 0xFF) - 128
            val normalizedAmplitude = amplitude / 128f * animationIntensity
            val y = centerY + normalizedAmplitude * height * 0.3f
            val x = i * stepX
            
            // Add flowing wave effect
            val flowY = y + sin(animationPhase * 2 + i * 0.05f) * 20f * animationIntensity
            
            if (i == 0) {
                path.moveTo(x, flowY)
            } else {
                path.lineTo(x, flowY)
            }
        }
        
        canvas.drawPath(path, waveformPaint)
    }
    
    private fun drawLightning(canvas: Canvas) {
        if (lightningActive && lightningOpacity > 0f) {
            lightningPaint.alpha = (lightningOpacity * 255).toInt()
            canvas.drawPath(lightningPath, lightningPaint)
        }
    }
    
    private fun drawParticles(canvas: Canvas) {
        particles.forEach { particle ->
            if (particle.life > 0f) {
                particlePaint.alpha = (particle.life * 255).toInt()
                val size = particle.life * 8f * animationIntensity
                canvas.drawCircle(particle.x, particle.y, size, particlePaint)
            }
        }
    }
    
    private fun drawRipples(canvas: Canvas) {
        ripples.forEach { ripple ->
            if (ripple.life > 0f) {
                ripplePaint.alpha = (ripple.life * 128).toInt()
                canvas.drawCircle(
                    ripple.x, 
                    ripple.y, 
                    ripple.radius * (1f - ripple.life), 
                    ripplePaint
                )
            }
        }
    }
    
    private fun drawProgressLine(canvas: Canvas) {
        if (width <= 0 || height <= 0) return
        
        val progressX = currentProgress * width
        val topY = height * 0.1f
        val bottomY = height * 0.9f
        
        // Draw main progress line
        canvas.drawLine(progressX, topY, progressX, bottomY, progressPaint)
        
        // Draw animated glow effect
        val glowPaint = Paint(progressPaint).apply {
            strokeWidth = 12f
            alpha = (128 * (0.5f + 0.5f * sin(animationPhase * 3))).toInt()
        }
        canvas.drawLine(progressX, topY, progressX, bottomY, glowPaint)
    }
    
    override fun onTouchEvent(event: android.view.MotionEvent): Boolean {
        when (event.action) {
            android.view.MotionEvent.ACTION_DOWN,
            android.view.MotionEvent.ACTION_MOVE,
            android.view.MotionEvent.ACTION_UP -> {
                if (width > 0) {
                    val seekPosition = (event.x / width).coerceIn(0f, 1f)
                    if (event.action == android.view.MotionEvent.ACTION_UP) {
                        onSeekListener?.invoke(seekPosition)
                        
                        // Add ripple at touch position for visual feedback
                        addRipple(event.x, event.y)
                    }
                    return true
                }
            }
        }
        return super.onTouchEvent(event)
    }
    
    private fun updateParticles() {
        if (width <= 0 || height <= 0) return
        
        particles.forEach { particle ->
            particle.x += particle.vx
            particle.y += particle.vy
            particle.life -= 0.01f
            
            // Wrap around screen
            if (particle.x < 0) particle.x = width.toFloat()
            if (particle.x > width) particle.x = 0f
            if (particle.y < 0) particle.y = height.toFloat()
            if (particle.y > height) particle.y = 0f
            
            // Reset dead particles
            if (particle.life <= 0f) {
                particle.x = Random.nextFloat() * width
                particle.y = Random.nextFloat() * height
                particle.life = 1f
            }
        }
    }
    
    /**
     * Trigger lightning effect
     */
    fun triggerLightning() {
        if (!enableLightning || width <= 0 || height <= 0) return
        
        lightningAnimator?.cancel()
        generateLightningPath()
        
        lightningActive = true
        lightningAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = LIGHTNING_DURATION
            addUpdateListener { animation ->
                lightningOpacity = animation.animatedValue as Float
                invalidate()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    lightningActive = false
                }
            })
        }
        lightningAnimator?.start()
    }
    
    /**
     * Add ripple effect at position
     */
    fun addRipple(x: Float, y: Float) {
        if (!enableRipples || width <= 0 || height <= 0) return
        
        ripples.removeAll { it.life <= 0f }
        ripples.add(Ripple(x, y, min(width, height) * 0.5f, 1f))
        
        if (rippleAnimator?.isRunning != true) {
            rippleAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 1000
                addUpdateListener {
                    ripples.forEach { ripple ->
                        ripple.life -= 0.02f
                    }
                    ripples.removeAll { it.life <= 0f }
                    invalidate()
                }
            }
            rippleAnimator?.start()
        }
    }
    
    private fun generateLightningPath() {
        lightningPath.reset()
        val startX = Random.nextFloat() * width
        val startY = Random.nextFloat() * height * 0.3f
        val endX = Random.nextFloat() * width
        val endY = height - Random.nextFloat() * height * 0.3f
        
        lightningPath.moveTo(startX, startY)
        
        val segments = 8
        for (i in 1..segments) {
            val progress = i.toFloat() / segments
            val x = startX + (endX - startX) * progress + (Random.nextFloat() - 0.5f) * 100f
            val y = startY + (endY - startY) * progress + (Random.nextFloat() - 0.5f) * 50f
            lightningPath.lineTo(x, y)
        }
    }
    
    /**
     * Set waveform data for visualization
     */
    fun setWaveformData(data: ByteArray?) {
        waveformData = data
        invalidate()
        
        // Trigger effects based on audio intensity
        data?.let {
            val intensity = it.map { byte -> abs(byte.toInt()) }.average()
            if (intensity > 100 && Random.nextFloat() < 0.1f) {
                triggerLightning()
            }
        }
    }
    
    /**
     * Set spectrum data for visualization
     */
    fun setSpectrumData(data: FloatArray?) {
        spectrumData = data
        invalidate()
        
        // Add ripples based on bass frequencies
        data?.let {
            if (it.isNotEmpty() && it[0] > 150f && Random.nextFloat() < 0.2f) {
                addRipple(Random.nextFloat() * width, Random.nextFloat() * height)
            }
        }
    }
    
    /**
     * Start visualization
     */
    fun startVisualization() {
        isAnimating = true
    }
    
    /**
     * Stop visualization
     */
    fun stopVisualization() {
        isAnimating = false
        lightningAnimator?.cancel()
        particleAnimator?.cancel()
        rippleAnimator?.cancel()
        releaseVisualizer()
    }
    
    /**
     * Apply appearance preferences to customize the visualizer
     */
    fun applyAppearancePreferences(prefs: AppearancePreferences) {
        try {
            // Update colors based on appearance preferences
            if (prefs.synthWaveUseCustomColors) {
                // Update waveform paint
                waveformPaint.shader = LinearGradient(
                    0f, 0f, 0f, 500f,
                    prefs.synthWavePrimaryColor,
                    prefs.synthWaveSecondaryColor,
                    Shader.TileMode.CLAMP
                )
                
                // Update spectrum paint
                spectrumPaint.shader = LinearGradient(
                    0f, 0f, 0f, 300f,
                    intArrayOf(
                        prefs.synthWavePrimaryColor,
                        prefs.synthWaveSecondaryColor,
                        prefs.synthWaveGlowColor,
                        prefs.accentColor
                    ),
                    floatArrayOf(0f, 0.3f, 0.7f, 1f),
                    Shader.TileMode.CLAMP
                )
                
                // Update grid paint
                gridPaint.color = prefs.synthWavePrimaryColor
                
                // Update particle paint
                particlePaint.color = prefs.synthWaveGlowColor
                
                // Update ripple paint
                ripplePaint.color = prefs.synthWaveSecondaryColor
                
                // Update progress paint
                progressPaint.color = prefs.accentColor
                progressPaint.setShadowLayer(8f, 0f, 0f, prefs.accentColor)
            }
            
            // Update animation intensity
            animationIntensity = prefs.synthWaveAnimationIntensity
            
            invalidate()
        } catch (e: Exception) {
            android.util.Log.w(TAG, "Error applying appearance preferences", e)
        }
    }
    
    /**
     * Set seek listener for progress line interaction
     */
    fun setOnSeekListener(listener: ((Float) -> Unit)?) {
        onSeekListener = listener
    }
    
    /**
     * Set the visualizer mode
     */
    fun setVisualizerMode(mode: VisualizerMode) {
        currentMode = mode
        invalidate()
    }
    
    /**
     * Get the current visualizer mode
     */
    fun getVisualizerMode(): VisualizerMode = currentMode
    
    /**
     * Set audio session for visualizer
     */
    fun setAudioSession(sessionId: Int) {
        audioSessionId = sessionId
        setupVisualizer()
    }
    
    /**
     * Update progress for progress line display
     */
    fun updateProgress(currentPosition: Long, duration: Long) {
        if (duration > 0) {
            currentProgress = (currentPosition.toFloat() / duration.toFloat()).coerceIn(0f, 1f)
            invalidate()
        }
    }
    
    private fun setupVisualizer() {
        try {
            releaseVisualizer()
            
            // Only setup if we have a valid audio session (not 0 which is the global session)
            if (audioSessionId != 0) {
                try {
                    visualizer = Visualizer(audioSessionId).apply {
                        captureSize = Visualizer.getCaptureSizeRange()[1]
                        setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                            override fun onWaveFormDataCapture(
                                visualizer: Visualizer,
                                waveform: ByteArray,
                                samplingRate: Int
                            ) {
                                post {
                                    setWaveformData(waveform)
                                }
                            }
                            
                            override fun onFftDataCapture(
                                visualizer: Visualizer,
                                fft: ByteArray,
                                samplingRate: Int
                            ) {
                                // Convert FFT data to spectrum data
                                val spectrum = FloatArray(fft.size / 2)
                                for (i in spectrum.indices) {
                                    val real = fft[i * 2].toFloat()
                                    val imaginary = fft[i * 2 + 1].toFloat()
                                    spectrum[i] = sqrt(real * real + imaginary * imaginary)
                                }
                                post {
                                    setSpectrumData(spectrum)
                                }
                            }
                        }, Visualizer.getMaxCaptureRate() / 2, true, true)
                        
                        enabled = true
                    }
                } catch (ve: Exception) {
                    android.util.Log.w(TAG, "Could not create Visualizer with session $audioSessionId: ${ve.message}")
                    visualizer = null
                    // Continue without visualizer - view will still render with default animations
                }
            } else {
                android.util.Log.d(TAG, "Audio session ID is 0 (global session), skipping visualizer setup")
            }
        } catch (e: Exception) {
            android.util.Log.w(TAG, "Error setting up visualizer", e)
            visualizer = null
        }
    }
    
    private fun releaseVisualizer() {
        try {
            visualizer?.apply {
                enabled = false
                release()
            }
        } catch (e: Exception) {
            android.util.Log.w(TAG, "Error releasing visualizer", e)
        }
        visualizer = null
    }
    
    /**
     * Data classes for effects
     */
    private data class Particle(
        var x: Float,
        var y: Float,
        var vx: Float,
        var vy: Float,
        var life: Float
    )
    
    private data class Ripple(
        val x: Float,
        val y: Float,
        val radius: Float,
        var life: Float
    )
}