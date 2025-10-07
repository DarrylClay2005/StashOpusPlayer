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
    private val particlePath = Path()

    private var phase = 0f
    private var lastAmp = 0f
    private var bassLevel = 0f
    private var midLevel = 0f
    private var trebleLevel = 0f
    private val particles = mutableListOf<Particle>()
    
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
        var size: Float
    )
    
    private val frameRunnable = object : Runnable {
        override fun run() {
            phase += 0.05f + (bassLevel * 0.02f) // Variable phase speed based on bass
            updateParticles()
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
        
        particles.add(
            Particle(
                x = kotlin.random.Random.nextFloat() * w,
                y = h * 0.5f + (kotlin.random.Random.nextFloat() - 0.5f) * h * 0.3f,
                vx = (kotlin.random.Random.nextFloat() - 0.5f) * 20f,
                vy = (kotlin.random.Random.nextFloat() - 0.5f) * 15f,
                life = 1f,
                maxLife = 1f,
                size = 2f + kotlin.random.Random.nextFloat() * 4f
            )
        )
    }
    
    private fun updateParticles() {
        val iterator = particles.iterator()
        while (iterator.hasNext()) {
            val particle = iterator.next()
            particle.x += particle.vx
            particle.y += particle.vy
            particle.life -= 0.02f
            particle.vy += 0.5f // gravity effect
            
            if (particle.life <= 0f || particle.y > height || particle.x < 0 || particle.x > width) {
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
        particlePath.reset()

        // Calculate progress percentage
        val progress = if (progressMode && totalDuration > 0) {
            (currentPosition.toFloat() / totalDuration.toFloat()).coerceIn(0f, 1f)
        } else {
            1f // Full width when not in progress mode
        }

        // Use audio-reactive amplitude and frequency-based modulation
        val baseAmp = h * 0.15f
        val reactiveAmp = baseAmp * (0.3f + lastAmp * 1.2f)
        val bassAmp = reactiveAmp * (1f + bassLevel * 0.8f)
        val midAmp = reactiveAmp * (1f + midLevel * 0.6f)
        val trebleAmp = reactiveAmp * (1f + trebleLevel * 0.4f)

        // Dynamic frequencies based on audio content
        val freq1 = 2.0 + (bassLevel * 1.5)
        val freq2 = 3.0 + (midLevel * 2.0)
        val freq3 = 1.5 + (trebleLevel * 2.5)
        
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
            
            // Multi-layered waves with different frequency responses
            val y1 = centerY + bassAmp * waveIntensity * sin(2 * PI * (freq1 * t + phase)).toFloat()
            val y2 = centerY + midAmp * waveIntensity * 0.8f * sin(2 * PI * (freq2 * t + phase * 0.7 + 0.33)).toFloat()
            val yg = centerY + trebleAmp * waveIntensity * 0.6f * sin(2 * PI * (freq3 * t + phase * 1.3 + 0.1)).toFloat()
            
            // Add subtle noise based on waveform data (only to active portion)
            val noiseIndex = (t * (waveform.size - 1)).toInt()
            val noise = if (noiseIndex < waveform.size && x <= activeWidth) waveform[noiseIndex].toFloat() / 256f else 0f
            val y1Noise = y1 + noise * bassAmp * waveIntensity * 0.1f
            val y2Noise = y2 + noise * midAmp * waveIntensity * 0.08f
            
            if (i == 0) {
                path1.moveTo(x, y1Noise)
                path2.moveTo(x, y2Noise)
                glowPath.moveTo(x, yg)
            } else {
                path1.lineTo(x, y1Noise)
                path2.lineTo(x, y2Noise)
                glowPath.lineTo(x, yg)
            }
        }
        
        // Update paint colors based on frequency content
        val bassColor = (bassLevel * 255).toInt().coerceIn(0, 255)
        val midColor = (midLevel * 255).toInt().coerceIn(0, 255)
        val trebleColor = (trebleLevel * 255).toInt().coerceIn(0, 255)
        
        // Create dynamic paint objects with adjusted properties
        val dynamicPaint1 = Paint(paint1).apply {
            alpha = (180 + (bassLevel * 75)).toInt().coerceIn(100, 255)
        }
        val dynamicPaint2 = Paint(paint2).apply {
            alpha = (160 + (midLevel * 95)).toInt().coerceIn(100, 255)
        }
        val dynamicGlowPaint = Paint(glowPaint).apply {
            alpha = (90 + (trebleLevel * 165)).toInt().coerceIn(50, 255)
        }
        
        // Draw enhanced glow with multiple layers
        canvas.drawPath(glowPath, dynamicGlowPaint)
        
        // Draw secondary glow for intense moments
        if (bassLevel > 0.7f || midLevel > 0.7f) {
            val intensePaint = Paint(dynamicGlowPaint).apply {
                strokeWidth = dp(15f)
                alpha = ((bassLevel + midLevel) * 60).toInt().coerceIn(0, 120)
                maskFilter = BlurMaskFilter(dp(12f), BlurMaskFilter.Blur.NORMAL)
            }
            canvas.drawPath(glowPath, intensePaint)
        }
        
        // Draw main waves
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
            val alpha = (particle.life * 255).toInt().coerceIn(0, 255)
            
            // Create new paint with current alpha
            val currentParticlePaint = Paint(particlePaint).apply {
                this.alpha = alpha  // Use 'this.alpha' to avoid scoping conflict
            }
            
            // Scale size based on life and bass level
            val size = particle.size * (particle.life + bassLevel * 0.5f)
            canvas.drawCircle(particle.x, particle.y, size, currentParticlePaint)
            
            // Add glow effect to particles during intense moments
            if (bassLevel > 0.5f) {
                val glowAlpha = (alpha * 0.3f).toInt()
                val glowParticlePaint = Paint(particlePaint).apply {
                    this.alpha = glowAlpha
                    maskFilter = BlurMaskFilter(size * 0.8f, BlurMaskFilter.Blur.NORMAL)
                }
                canvas.drawCircle(particle.x, particle.y, size * 1.5f, glowParticlePaint)
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
