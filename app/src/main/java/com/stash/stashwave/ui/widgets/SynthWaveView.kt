package com.stash.opusplayer.ui.widgets

import android.content.Context
import android.graphics.*
import android.media.audiofx.Visualizer
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import androidx.core.content.ContextCompat
import com.stash.opusplayer.R
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.cos
import kotlin.math.abs
import kotlin.math.sqrt

class SynthWaveView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private var visualizer: Visualizer? = null
    private val waveform = ByteArray(1024)
    private val fftData = ByteArray(1024)
    private val frequencyBands = FloatArray(8) // 8 frequency bands for better reactivity
    
    // Enhanced paint objects for better visuals
    private val paint1 = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(2f)
        color = ContextCompat.getColor(context, R.color.accent_color)
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val paint2 = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(3.5f)
        color = ContextCompat.getColor(context, R.color.accent_gradient_end)
        alpha = 180
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(10f)
        color = ContextCompat.getColor(context, R.color.accent_gradient_start)
        maskFilter = BlurMaskFilter(dp(8f), BlurMaskFilter.Blur.NORMAL)
        alpha = 120
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    
    // Additional paint for particle effects
    private val particlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = ContextCompat.getColor(context, R.color.accent_color)
        alpha = 150
    }

    private val path1 = Path()
    private val path2 = Path()
    private val glowPath = Path()
    private val path4 = Path()
    private val path5 = Path()
    private val particlePath = Path()

    private var phase = 0f
    private var lastAmp = 0f
    private var bassLevel = 0f
    private var midLevel = 0f
    private var trebleLevel = 0f
    private val particles = mutableListOf<Particle>()
    private val lightningBolts = mutableListOf<LightningBolt>()
    private val ripples = mutableListOf<Ripple>()
    
    // Enhanced animation variables
    private var waveIntensityAnimator = 0f
    private var bassDropDetector = 0f
    private var previousBassLevel = 0f
    private var pulseScale = 1f
    private var colorShiftPhase = 0f
    private var energyLevel = 0f
    private var beatDetectionCounter = 0
    private var lastBeatTime = 0L
    private var bpm = 120f // Estimated BPM for sync effects
    
    // Progress and customization
    private var currentPosition: Long = 0L
    private var totalDuration: Long = 0L
    private var progressMode = true
    private var useCustomColors = false
    
    // Appearance preferences reference
    private var appearancePrefs: com.stash.opusplayer.ui.appearance.AppearancePreferences? = null
    
    // Audio session for specific track visualization
    private var audioSession: Int = 0
    
    // Touch handling for seeking
    private var onSeekListener: ((Float) -> Unit)? = null
    private var isDragging = false

    // Particle class for visual effects
    private data class Particle(
        var x: Float,
        var y: Float,
        var vx: Float,
        var vy: Float,
        var life: Float,
        var maxLife: Float,
        var size: Float,
        var color: Int = 0,
        var rotation: Float = 0f,
        var rotationSpeed: Float = 0f,
        var trail: MutableList<Pair<Float, Float>> = mutableListOf()
    )
    
    // Lightning bolt class for intense moments
    private data class LightningBolt(
        var startX: Float,
        var startY: Float,
        var endX: Float,
        var endY: Float,
        var segments: List<Pair<Float, Float>>,
        var life: Float,
        var intensity: Float
    )
    
    // Ripple effect for bass drops
    private data class Ripple(
        var centerX: Float,
        var centerY: Float,
        var radius: Float,
        var maxRadius: Float,
        var life: Float,
        var intensity: Float
    )
    
    private val frameRunnable = object : Runnable {
        override fun run() {
            // Enhanced phase calculation with multiple frequencies
            phase += 0.05f + (bassLevel * 0.02f) // Variable phase speed based on bass
            colorShiftPhase += 0.03f + (energyLevel * 0.01f)
            
            // Update all animation elements
            updateAnimationVariables()
            updateParticles()
            updateLightningBolts()
            updateRipples()
            
            // Detect bass drops and beats
            detectBassDrops()
            detectBeats()
            
            invalidate()
            postOnAnimation(this)
        }
    }

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null) // allow blur mask glow
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        start()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stop()
    }

    fun start() {
        try {
            // Use specific audio session if set, otherwise fall back to global output (session 0)
            visualizer = Visualizer(audioSession).apply {
                captureSize = Visualizer.getCaptureSizeRange()[1]
                setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?,
                        bytes: ByteArray?,
                        samplingRate: Int
                    ) {
                        if (bytes != null) {
                            System.arraycopy(bytes, 0, waveform, 0, waveform.size.coerceAtMost(bytes.size))
                            // compute a simple amplitude
                            val avg = bytes.take(128).map { kotlin.math.abs(it.toInt()) }.average()
                            val target = (avg / 128.0).toFloat().coerceIn(0f, 1f)
                            // smooth toward target
                            lastAmp += (target - lastAmp) * 0.15f
                            
                            // Create particles based on amplitude peaks
                            if (target > 0.6f && particles.size < 20) {
                                spawnParticle()
                            }
                        }
                    }

                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        bytes: ByteArray?,
                        samplingRate: Int
                    ) {
                        if (bytes != null) {
                            System.arraycopy(bytes, 0, fftData, 0, fftData.size.coerceAtMost(bytes.size))
                            // Process FFT data for frequency bands
                            processFrequencyData(bytes)
                        }
                    }
                }, Visualizer.getMaxCaptureRate() / 2, true, true)
                enabled = true
            }
        } catch (_: Exception) {
            // Visualizer may fail on some devices—fallback to pure synth
            visualizer?.release()
            visualizer = null
        }
        removeCallbacks(frameRunnable)
        post(frameRunnable)
    }

    fun stop() {
        removeCallbacks(frameRunnable)
        try { visualizer?.enabled = false } catch (_: Exception) {}
        try { visualizer?.release() } catch (_: Exception) {}
        visualizer = null
        particles.clear()
        lightningBolts.clear()
        ripples.clear()
    }
    
    /**
     * Update the current playback position for progress mode
     */
    fun updateProgress(currentPosition: Long, totalDuration: Long) {
        this.currentPosition = currentPosition.coerceAtLeast(0L)
        this.totalDuration = totalDuration.coerceAtLeast(1L) // Avoid division by zero
    }
    
    /**
     * Apply appearance preferences to the visualizer
     */
    fun applyAppearancePreferences(prefs: com.stash.opusplayer.ui.appearance.AppearancePreferences) {
        this.appearancePrefs = prefs
        this.progressMode = prefs.synthWaveProgressMode
        this.useCustomColors = prefs.synthWaveUseCustomColors
        
        // Update paint colors if using custom colors
        if (useCustomColors) {
            paint1.color = prefs.synthWavePrimaryColor
            paint2.color = prefs.synthWaveSecondaryColor
            glowPaint.color = prefs.synthWaveGlowColor
            particlePaint.color = prefs.synthWavePrimaryColor
        } else {
            // Use default colors
            paint1.color = ContextCompat.getColor(context, R.color.accent_color)
            paint2.color = ContextCompat.getColor(context, R.color.accent_gradient_end)
            glowPaint.color = ContextCompat.getColor(context, R.color.accent_gradient_start)
            particlePaint.color = ContextCompat.getColor(context, R.color.accent_color)
        }
    }
    
    /**
     * Set the audio session ID to visualize specific track
     */
    fun setAudioSession(sessionId: Int) {
        if (audioSession != sessionId) {
            audioSession = sessionId
            // Restart visualizer with new session
            if (visualizer != null) {
                stop()
                start()
            }
        }
    }
    
    /**
     * Set listener for seek events when user drags the progress line
     */
    fun setOnSeekListener(listener: (Float) -> Unit) {
        onSeekListener = listener
    }
    
    private fun processFrequencyData(fftBytes: ByteArray) {
        // Extract frequency bands from FFT data
        val bandSize = fftBytes.size / 8
        for (i in 0 until 8) {
            val start = i * bandSize
            val end = (start + bandSize).coerceAtMost(fftBytes.size)
            var sum = 0f
            for (j in start until end) {
                val real = fftBytes[j].toInt()
                val imag = if (j + 1 < fftBytes.size) fftBytes[j + 1].toInt() else 0
                sum += kotlin.math.sqrt((real * real + imag * imag).toDouble()).toFloat()
            }
            val target = (sum / bandSize).coerceIn(0f, 128f) / 128f
            // Smooth the frequency band values
            frequencyBands[i] += (target - frequencyBands[i]) * 0.2f
        }
        
        // Update specific frequency levels
        bassLevel = (frequencyBands[0] + frequencyBands[1]) / 2f
        midLevel = (frequencyBands[2] + frequencyBands[3] + frequencyBands[4]) / 3f
        trebleLevel = (frequencyBands[5] + frequencyBands[6] + frequencyBands[7]) / 3f
    }
    
    private fun spawnParticle() {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return
        
        val baseColor = if (useCustomColors) {
            appearancePrefs?.synthWavePrimaryColor ?: paint1.color
        } else {
            paint1.color
        }
        
        particles.add(
            Particle(
                x = kotlin.random.Random.nextFloat() * w,
                y = h * 0.5f + (kotlin.random.Random.nextFloat() - 0.5f) * h * 0.3f,
                vx = (kotlin.random.Random.nextFloat() - 0.5f) * 20f * (1f + energyLevel),
                vy = (kotlin.random.Random.nextFloat() - 0.5f) * 15f * (1f + energyLevel),
                life = 1f,
                maxLife = 1f + kotlin.random.Random.nextFloat() * 2f,
                size = 2f + kotlin.random.Random.nextFloat() * 6f * (1f + bassLevel),
                color = baseColor,
                rotation = kotlin.random.Random.nextFloat() * 360f,
                rotationSpeed = (kotlin.random.Random.nextFloat() - 0.5f) * 10f
            )
        )
    }
    
    private fun updateAnimationVariables() {
        // Update energy level based on all frequency bands
        energyLevel = (bassLevel + midLevel + trebleLevel) / 3f
        
        // Smooth wave intensity animator
        val targetIntensity = energyLevel * 2f
        waveIntensityAnimator += (targetIntensity - waveIntensityAnimator) * 0.1f
        
        // Update pulse scale based on energy
        pulseScale = 1f + (energyLevel * 0.3f * sin(phase * 4).toFloat())
        
        // Store previous bass level for drop detection
        previousBassLevel = bassLevel
    }
    
    private fun detectBassDrops() {
        val currentTime = System.currentTimeMillis()
        bassDropDetector += (bassLevel - previousBassLevel) * 10f
        bassDropDetector *= 0.95f // Decay
        
        // Spawn lightning on significant bass drops
        if (bassDropDetector > 1.5f && currentTime - lastBeatTime > 200) {
            spawnLightningBolt()
            spawnRipple(width * 0.5f, height * 0.5f, bassDropDetector)
            lastBeatTime = currentTime
        }
    }
    
    private fun detectBeats() {
        val currentTime = System.currentTimeMillis()
        if (bassLevel > 0.6f && currentTime - lastBeatTime > (60000f / bpm).toLong()) {
            beatDetectionCounter++
            spawnRipple(
                kotlin.random.Random.nextFloat() * width,
                height * 0.5f,
                bassLevel
            )
            lastBeatTime = currentTime
            
            // Adjust BPM estimate
            if (beatDetectionCounter > 4) {
                val timeDiff = currentTime - lastBeatTime
                if (timeDiff > 0) {
                    bpm = kotlin.math.min(200f, kotlin.math.max(60f, 60000f / timeDiff))
                }
            }
        }
    }
    
    private fun updateParticles() {
        val iterator = particles.iterator()
        while (iterator.hasNext()) {
            val particle = iterator.next()
            
            // Update trail
            particle.trail.add(0, Pair(particle.x, particle.y))
            if (particle.trail.size > 8) {
                particle.trail.removeAt(particle.trail.size - 1)
            }
            
            // Update position with enhanced physics
            particle.x += particle.vx * (1f + energyLevel * 0.5f)
            particle.y += particle.vy * (1f + energyLevel * 0.5f)
            particle.rotation += particle.rotationSpeed
            particle.life -= 0.02f * (1f / particle.maxLife)
            particle.vy += 0.5f // gravity effect
            
            // Add wind effect based on treble
            particle.vx += (trebleLevel * 2f - 1f) * 0.5f
            
            if (particle.life <= 0f || particle.y > height + 50 || 
                particle.x < -50 || particle.x > width + 50) {
                iterator.remove()
            }
        }
    }
    
    private fun spawnLightningBolt() {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return
        
        val startX = kotlin.random.Random.nextFloat() * w
        val startY = h * 0.3f
        val endX = kotlin.random.Random.nextFloat() * w
        val endY = h * 0.7f
        
        // Create jagged lightning segments
        val segments = mutableListOf<Pair<Float, Float>>()
        val numSegments = 8 + (bassLevel * 12).toInt()
        
        for (i in 0..numSegments) {
            val t = i.toFloat() / numSegments
            val x = startX + (endX - startX) * t + (kotlin.random.Random.nextFloat() - 0.5f) * 30f
            val y = startY + (endY - startY) * t + (kotlin.random.Random.nextFloat() - 0.5f) * 20f
            segments.add(Pair(x, y))
        }
        
        lightningBolts.add(
            LightningBolt(
                startX = startX,
                startY = startY,
                endX = endX,
                endY = endY,
                segments = segments,
                life = 0.8f + kotlin.random.Random.nextFloat() * 0.4f,
                intensity = bassLevel
            )
        )
    }
    
    private fun updateLightningBolts() {
        val iterator = lightningBolts.iterator()
        while (iterator.hasNext()) {
            val bolt = iterator.next()
            bolt.life -= 0.05f
            
            if (bolt.life <= 0f) {
                iterator.remove()
            }
        }
    }
    
    private fun spawnRipple(centerX: Float, centerY: Float, intensity: Float) {
        ripples.add(
            Ripple(
                centerX = centerX,
                centerY = centerY,
                radius = 0f,
                maxRadius = 100f + intensity * 150f,
                life = 1f,
                intensity = intensity
            )
        )
    }
    
    private fun updateRipples() {
        val iterator = ripples.iterator()
        while (iterator.hasNext()) {
            val ripple = iterator.next()
            ripple.radius += (ripple.maxRadius - ripple.radius) * 0.15f
            ripple.life -= 0.03f
            
            if (ripple.life <= 0f || ripple.radius >= ripple.maxRadius * 0.98f) {
                iterator.remove()
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        val centerY = h * 0.5f

        // Prepare paths
        path1.reset()
        path2.reset()
        glowPath.reset()
        path4.reset()
        path5.reset()
        particlePath.reset()

        // Calculate progress percentage
        val progress = if (progressMode && totalDuration > 0) {
            (currentPosition.toFloat() / totalDuration.toFloat()).coerceIn(0f, 1f)
        } else {
            1f // Full width when not in progress mode
        }

        // Use audio-reactive amplitude with enhanced animation
        val baseAmp = h * 0.15f * pulseScale
        val reactiveAmp = baseAmp * (0.3f + lastAmp * 1.2f + waveIntensityAnimator * 0.3f)
        val bassAmp = reactiveAmp * (1f + bassLevel * 1.2f + bassDropDetector * 0.5f)
        val midAmp = reactiveAmp * (1f + midLevel * 0.8f)
        val trebleAmp = reactiveAmp * (1f + trebleLevel * 0.6f)

        // Dynamic frequencies with enhanced modulation and beat sync
        val freq1 = 2.0 + (bassLevel * 1.8 + sin(phase * 0.5) * 0.3)
        val freq2 = 3.0 + (midLevel * 2.5 + sin(phase * 0.7 + PI/4) * 0.5)
        val freq3 = 1.5 + (trebleLevel * 3.0 + sin(phase * 0.3 + PI/2) * 0.2)
        
        // Additional frequencies for layered waves
        val freq4 = 4.0 + (energyLevel * 2.0 + sin(phase * 0.2) * 0.4)
        val freq5 = 0.8 + (bassDropDetector * 0.5 + sin(phase * 0.9) * 0.3)
        
        // Calculate the active width based on progress
        val activeWidth = if (progressMode) w * progress else w
        val samples = 150 // Higher resolution for smoother curves
        
        for (i in 0..samples) {
            val t = i.toFloat() / samples
            val x = t * w
            
            // In progress mode, only draw waves up to the current position
            val waveIntensity = if (progressMode) {
                if (x <= activeWidth) {
                    // Full intensity for completed portion
                    1f
                } else {
                    // Faded intensity for future portion
                    0.1f + 0.05f * sin(2 * PI * (t * 8 + phase * 2)).toFloat() // Subtle preview wave
                }
            } else {
                1f // Full intensity when not in progress mode
            }
            
            // Multi-layered waves with enhanced harmonics and frequency responses
            val y1 = centerY + bassAmp * waveIntensity * sin(2 * PI * (freq1 * t + phase)).toFloat() * (1f + sin(colorShiftPhase * 2).toFloat() * 0.1f)
            val y2 = centerY + midAmp * waveIntensity * 0.8f * sin(2 * PI * (freq2 * t + phase * 0.7 + 0.33)).toFloat() * (1f + sin(colorShiftPhase * 1.5).toFloat() * 0.08f)
            val yg = centerY + trebleAmp * waveIntensity * 0.6f * sin(2 * PI * (freq3 * t + phase * 1.3 + 0.1)).toFloat() * (1f + sin(colorShiftPhase * 3).toFloat() * 0.05f)
            
            // Additional harmonic layers for richer visualization
            val y4 = centerY + reactiveAmp * waveIntensity * 0.4f * sin(2 * PI * (freq4 * t + phase * 0.5 + 0.5)).toFloat()
            val y5 = centerY + bassAmp * waveIntensity * 0.3f * sin(2 * PI * (freq5 * t + phase * 2.1 + 0.8)).toFloat()
            
            // Add subtle noise based on waveform data (only to active portion)
            val noiseIndex = (t * (waveform.size - 1)).toInt()
            val noise = if (noiseIndex < waveform.size && x <= activeWidth) waveform[noiseIndex].toFloat() / 256f else 0f
            val y1Noise = y1 + noise * bassAmp * waveIntensity * 0.1f
            val y2Noise = y2 + noise * midAmp * waveIntensity * 0.08f
            
            if (i == 0) {
                path1.moveTo(x, y1Noise)
                path2.moveTo(x, y2Noise)
                glowPath.moveTo(x, yg)
                path4.moveTo(x, y4)
                path5.moveTo(x, y5)
            } else {
                path1.lineTo(x, y1Noise)
                path2.lineTo(x, y2Noise)
                glowPath.lineTo(x, yg)
                path4.lineTo(x, y4)
                path5.lineTo(x, y5)
            }
        }
        
        // Enhanced dynamic color modulation
        val bassColor = (bassLevel * 255).toInt().coerceIn(0, 255)
        val midColor = (midLevel * 255).toInt().coerceIn(0, 255)
        val trebleColor = (trebleLevel * 255).toInt().coerceIn(0, 255)
        
        // Color shifting based on energy and beat detection
        val colorShift = (sin(colorShiftPhase).toFloat() * 0.2f + 0.8f)
        val energyColorMod = (1f + energyLevel * 0.5f).coerceIn(0.5f, 1.5f)
        
        // Create enhanced dynamic paint objects with color modulation
        val dynamicPaint1 = Paint(paint1).apply {
            alpha = (180 + (bassLevel * 75 * energyColorMod)).toInt().coerceIn(100, 255)
            if (bassDropDetector > 1f) {
                strokeWidth = dp(3f + bassDropDetector * 2f)
            }
        }
        val dynamicPaint2 = Paint(paint2).apply {
            alpha = (160 + (midLevel * 95 * energyColorMod)).toInt().coerceIn(100, 255)
            if (energyLevel > 0.7f) {
                strokeWidth = dp(4.5f + energyLevel * 1.5f)
            }
        }
        val dynamicGlowPaint = Paint(glowPaint).apply {
            alpha = (90 + (trebleLevel * 165 * energyColorMod)).toInt().coerceIn(50, 255)
            if (energyLevel > 0.8f) {
                maskFilter = BlurMaskFilter(dp(12f + energyLevel * 8f), BlurMaskFilter.Blur.NORMAL)
            }
        }
        
        // Additional harmonic layer paints
        val harmonicPaint1 = Paint(paint1).apply {
            alpha = (120 + (energyLevel * 60)).toInt().coerceIn(50, 200)
            strokeWidth = dp(1.5f)
            color = Color.argb(
                alpha,
                (Color.red(paint1.color) * colorShift).toInt().coerceIn(0, 255),
                (Color.green(paint1.color) * colorShift).toInt().coerceIn(0, 255),
                (Color.blue(paint1.color) * colorShift * 1.2f).toInt().coerceIn(0, 255)
            )
        }
        
        val harmonicPaint2 = Paint(paint2).apply {
            alpha = (100 + (bassLevel * 80)).toInt().coerceIn(40, 180)
            strokeWidth = dp(2f)
            color = Color.argb(
                alpha,
                (Color.red(paint2.color) * colorShift * 1.1f).toInt().coerceIn(0, 255),
                (Color.green(paint2.color) * colorShift).toInt().coerceIn(0, 255),
                (Color.blue(paint2.color) * colorShift * 0.9f).toInt().coerceIn(0, 255)
            )
        }
        
        // Draw background ripples first
        drawRipples(canvas)
        
        // Draw enhanced glow with multiple layers
        canvas.drawPath(glowPath, dynamicGlowPaint)
        
        // Draw secondary glow for intense moments
        if (bassLevel > 0.7f || midLevel > 0.7f) {
            val intensePaint = Paint(dynamicGlowPaint).apply {
                strokeWidth = dp(15f + energyLevel * 10f)
                alpha = ((bassLevel + midLevel) * 60 * energyColorMod).toInt().coerceIn(0, 150)
                maskFilter = BlurMaskFilter(dp(12f + energyLevel * 6f), BlurMaskFilter.Blur.NORMAL)
            }
            canvas.drawPath(glowPath, intensePaint)
        }
        
        // Draw harmonic layers first (background)
        if (energyLevel > 0.3f) {
            canvas.drawPath(path5, harmonicPaint2)
            canvas.drawPath(path4, harmonicPaint1)
        }
        
        // Draw lightning bolts behind main waves
        drawLightningBolts(canvas)
        
        // Draw main waves with enhanced dynamics
        canvas.drawPath(path2, dynamicPaint2)
        canvas.drawPath(path1, dynamicPaint1)
        
        // Draw particles
        drawParticles(canvas)
        
        // Draw progress indicator line in progress mode
        if (progressMode && progress > 0f && progress < 1f) {
            val progressX = activeWidth
            val baseColor = if (useCustomColors) {
                appearancePrefs?.synthWavePrimaryColor ?: paint1.color
            } else {
                paint1.color
            }
            
            // Make the line more visible when being dragged
            val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = if (isDragging) dp(4f) else dp(2f)
                color = baseColor
                alpha = if (isDragging) 255 else 200
            }
            
            // Add glow effect when dragging
            if (isDragging) {
                val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = dp(8f)
                    color = baseColor
                    alpha = 100
                    maskFilter = BlurMaskFilter(dp(4f), BlurMaskFilter.Blur.NORMAL)
                }
                canvas.drawLine(progressX, h * 0.1f, progressX, h * 0.9f, glowPaint)
            }
            
            canvas.drawLine(progressX, h * 0.2f, progressX, h * 0.8f, progressPaint)
        }
    }
    
    private fun drawParticles(canvas: Canvas) {
        for (particle in particles) {
            val alpha = (particle.life * 255 * (particle.life / particle.maxLife)).toInt().coerceIn(0, 255)
            
            // Draw particle trail first
            if (particle.trail.size > 1) {
                val trailPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = dp(1f)
                    color = particle.color
                    strokeCap = Paint.Cap.ROUND
                }
                
                for (i in 1 until particle.trail.size) {
                    val trailAlpha = (alpha * (1f - i.toFloat() / particle.trail.size) * 0.6f).toInt()
                    trailPaint.alpha = trailAlpha
                    trailPaint.strokeWidth = dp(0.5f + (particle.trail.size - i) * 0.2f)
                    
                    val prev = particle.trail[i - 1]
                    val curr = particle.trail[i]
                    canvas.drawLine(prev.first, prev.second, curr.first, curr.second, trailPaint)
                }
            }
            
            // Create enhanced particle paint with dynamic colors
            val currentParticlePaint = Paint(particlePaint).apply {
                this.alpha = alpha
                color = Color.argb(
                    alpha,
                    (Color.red(particle.color) * (1f + sin(colorShiftPhase * 2).toFloat() * 0.1f)).toInt().coerceIn(0, 255),
                    (Color.green(particle.color) * (1f + sin(colorShiftPhase * 1.5).toFloat() * 0.1f)).toInt().coerceIn(0, 255),
                    (Color.blue(particle.color) * (1f + sin(colorShiftPhase * 3).toFloat() * 0.1f)).toInt().coerceIn(0, 255)
                )
            }
            
            // Scale size based on life, bass level, and energy
            val size = particle.size * (particle.life + bassLevel * 0.8f + energyLevel * 0.3f)
            
            // Save canvas state for rotation
            canvas.save()
            canvas.rotate(particle.rotation, particle.x, particle.y)
            
            // Draw main particle (can be shapes other than circles for variety)
            when (kotlin.random.Random.nextInt(3)) {
                0 -> canvas.drawCircle(particle.x, particle.y, size, currentParticlePaint)
                1 -> {
                    // Draw diamond shape
                    val path = Path().apply {
                        moveTo(particle.x, particle.y - size)
                        lineTo(particle.x + size * 0.7f, particle.y)
                        lineTo(particle.x, particle.y + size)
                        lineTo(particle.x - size * 0.7f, particle.y)
                        close()
                    }
                    canvas.drawPath(path, currentParticlePaint)
                }
                2 -> {
                    // Draw star shape for high energy particles
                    if (energyLevel > 0.6f) {
                        val starPath = createStarPath(particle.x, particle.y, size, size * 0.5f, 5)
                        canvas.drawPath(starPath, currentParticlePaint)
                    } else {
                        canvas.drawCircle(particle.x, particle.y, size, currentParticlePaint)
                    }
                }
            }
            
            canvas.restore()
            
            // Add enhanced glow effect for intense moments
            if (energyLevel > 0.5f) {
                val glowAlpha = (alpha * 0.4f * energyLevel).toInt()
                val glowSize = size * (1.5f + energyLevel * 0.8f)
                val glowParticlePaint = Paint(currentParticlePaint).apply {
                    this.alpha = glowAlpha
                    maskFilter = BlurMaskFilter(glowSize * 0.6f, BlurMaskFilter.Blur.NORMAL)
                }
                canvas.drawCircle(particle.x, particle.y, glowSize, glowParticlePaint)
            }
            
            // Add sparkle effect for very high energy
            if (energyLevel > 0.8f && kotlin.random.Random.nextFloat() < 0.3f) {
                val sparklePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE
                    setAlpha((alpha * 0.8f).toInt())
                }
                canvas.drawCircle(
                    particle.x + (kotlin.random.Random.nextFloat() - 0.5f) * size * 2,
                    particle.y + (kotlin.random.Random.nextFloat() - 0.5f) * size * 2,
                    1f,
                    sparklePaint
                )
            }
        }
    }
    
    private fun createStarPath(cx: Float, cy: Float, outerRadius: Float, innerRadius: Float, points: Int): Path {
        val path = Path()
        val angle = Math.PI / points
        
        for (i in 0 until points * 2) {
            val radius = if (i % 2 == 0) outerRadius else innerRadius
            val x = cx + (radius * kotlin.math.cos(i * angle)).toFloat()
            val y = cy + (radius * kotlin.math.sin(i * angle)).toFloat()
            
            if (i == 0) {
                path.moveTo(x, y)
            } else {
                path.lineTo(x, y)
            }
        }
        
        path.close()
        return path
    }
    
    private fun drawLightningBolts(canvas: Canvas) {
        for (bolt in lightningBolts) {
            val alpha = (bolt.life * 255 * bolt.intensity).toInt().coerceIn(0, 255)
            
            val lightningPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp(2f + bolt.intensity * 4f)
                color = Color.argb(
                    alpha,
                    255,
                    (200 + bolt.intensity * 55).toInt().coerceIn(0, 255),
                    (150 + bolt.intensity * 105).toInt().coerceIn(0, 255)
                )
                strokeCap = Paint.Cap.ROUND
                maskFilter = BlurMaskFilter(dp(3f), BlurMaskFilter.Blur.NORMAL)
            }
            
            // Draw lightning segments
            if (bolt.segments.size > 1) {
                for (i in 1 until bolt.segments.size) {
                    val start = bolt.segments[i - 1]
                    val end = bolt.segments[i]
                    canvas.drawLine(start.first, start.second, end.first, end.second, lightningPaint)
                }
            }
            
            // Add main lightning glow
            val glowPaint = Paint(lightningPaint).apply {
                strokeWidth = dp(8f + bolt.intensity * 6f)
                setAlpha((alpha * 0.3f).toInt())
                maskFilter = BlurMaskFilter(dp(8f), BlurMaskFilter.Blur.NORMAL)
            }
            
            if (bolt.segments.size > 1) {
                for (i in 1 until bolt.segments.size) {
                    val start = bolt.segments[i - 1]
                    val end = bolt.segments[i]
                    canvas.drawLine(start.first, start.second, end.first, end.second, glowPaint)
                }
            }
        }
    }
    
    private fun drawRipples(canvas: Canvas) {
        for (ripple in ripples) {
            val alpha = (ripple.life * 150 * ripple.intensity).toInt().coerceIn(0, 200)
            
            val ripplePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp(2f + ripple.intensity * 3f)
                color = if (useCustomColors) {
                    Color.argb(
                        alpha,
                        Color.red(appearancePrefs?.synthWaveSecondaryColor ?: paint2.color),
                        Color.green(appearancePrefs?.synthWaveSecondaryColor ?: paint2.color),
                        Color.blue(appearancePrefs?.synthWaveSecondaryColor ?: paint2.color)
                    )
                } else {
                    Color.argb(alpha, 100, 150, 255)
                }
                strokeCap = Paint.Cap.ROUND
            }
            
            // Draw concentric ripples
            val numRings = 3
            for (i in 0 until numRings) {
                val ringRadius = ripple.radius * (1f - i * 0.3f)
                val ringAlpha = (alpha * (1f - i * 0.3f)).toInt()
                ripplePaint.alpha = ringAlpha
                
                if (ringRadius > 0) {
                    canvas.drawCircle(ripple.centerX, ripple.centerY, ringRadius, ripplePaint)
                }
            }
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!progressMode || totalDuration <= 0) return super.onTouchEvent(event)
        
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                val x = event.x
                val progress = if (progressMode && totalDuration > 0) {
                    (currentPosition.toFloat() / totalDuration.toFloat()).coerceIn(0f, 1f)
                } else {
                    1f
                }
                val progressX = width * progress
                
                // Check if touch is near the progress line (within 30dp)
                val touchThreshold = 30 * resources.displayMetrics.density
                if (kotlin.math.abs(x - progressX) <= touchThreshold) {
                    isDragging = true
                    parent.requestDisallowInterceptTouchEvent(true)
                    return true
                }
            }
            MotionEvent.ACTION_MOVE -> {
                if (isDragging) {
                    val seekPosition = (event.x / width).coerceIn(0f, 1f)
                    onSeekListener?.invoke(seekPosition)
                    return true
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (isDragging) {
                    isDragging = false
                    parent.requestDisallowInterceptTouchEvent(false)
                    return true
                }
            }
        }
        return super.onTouchEvent(event)
    }
    
    private fun dp(v: Float) = v * resources.displayMetrics.density
}
