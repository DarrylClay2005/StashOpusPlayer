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
    
    // Animation preferences
    private var enableLightning: Boolean
        get() = prefs.getBoolean("synthwave_lightning", true)
        set(value) = prefs.edit().putBoolean("synthwave_lightning", value).apply()
    
    private var enableParticles: Boolean
        get() = prefs.getBoolean("synthwave_particles", true)
        set(value) = prefs.edit().putBoolean("synthwave_particles", value).apply()
    
    private var enableRipples: Boolean
        get() = prefs.getBoolean("synthwave_ripples", true)
        set(value) = prefs.edit().putBoolean("synthwave_ripples", value).apply()
    
    private var enableBreathing: Boolean
        get() = prefs.getBoolean("synthwave_breathing", true)
        set(value) = prefs.edit().putBoolean("synthwave_breathing", value).apply()
    
    private var enableColorShift: Boolean
        get() = prefs.getBoolean("synthwave_color_shift", true)
        set(value) = prefs.edit().putBoolean("synthwave_color_shift", value).apply()
    
    private var animationIntensity: Float
        get() = prefs.getFloat("synthwave_intensity", 1f)
        set(value) = prefs.edit().putFloat("synthwave_intensity", value).apply()

    init {
        setupAnimations()
        initializeParticles()
        setLayerType(LAYER_TYPE_HARDWARE, null)
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
        updateShaders()
        initializeParticles()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        
        // Apply breathing effect
        if (enableBreathing) {
            val scale = 1f + sin(breathingPhase) * 0.05f * animationIntensity
            canvas.scale(scale, scale, width / 2f, height / 2f)
        }
        
        // Draw background grid
        drawGrid(canvas)
        
        // Draw spectrum analyzer
        drawSpectrum(canvas)
        
        // Draw waveform
        drawWaveform(canvas)
        
        // Draw effects
        if (enableLightning) drawLightning(canvas)
        if (enableParticles) drawParticles(canvas)
        if (enableRipples) drawRipples(canvas)
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
    
    private fun updateParticles() {
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