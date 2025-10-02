package com.stash.stashwave.ui.widgets

import android.content.Context
import android.graphics.*
import android.media.audiofx.Visualizer
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import com.stash.stashwave.R
import kotlin.math.PI
import kotlin.math.sin

class SynthWaveView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private var visualizer: Visualizer? = null
    private val waveform = ByteArray(1024)

    private val paint1 = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(2f)
        color = ContextCompat.getColor(context, R.color.accent_color)
    }
    private val paint2 = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(3.5f)
        color = ContextCompat.getColor(context, R.color.accent_gradient_end)
        alpha = 180
    }
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(8f)
        color = ContextCompat.getColor(context, R.color.accent_gradient_start)
        maskFilter = BlurMaskFilter(dp(6f), BlurMaskFilter.Blur.NORMAL)
        alpha = 90
    }

    private val path1 = Path()
    private val path2 = Path()
    private val glowPath = Path()

    private var phase = 0f
    private var lastAmp = 0f

    private val frameRunnable = object : Runnable {
        override fun run() {
            phase += 0.04f
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
            // Visualizer on global output mix (session 0) to avoid wiring to player
            visualizer = Visualizer(0).apply {
                captureSize = Visualizer.getCaptureSizeRange()[1]
                setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?,
                        bytes: ByteArray?,
                        samplingRate: Int
                    ) {
                        if (bytes != null) System.arraycopy(bytes, 0, waveform, 0, waveform.size.coerceAtMost(bytes.size))
                        // compute a simple amplitude
                        val avg = bytes?.take(128)?.map { kotlin.math.abs(it.toInt()) }?.average() ?: 0.0
                        val target = (avg / 128.0).toFloat().coerceIn(0f, 1f)
                        // smooth toward target
                        lastAmp += (target - lastAmp) * 0.1f
                    }

                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        bytes: ByteArray?,
                        samplingRate: Int
                    ) { /* not used */ }
                }, Visualizer.getMaxCaptureRate() / 2, true, false)
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

        // Use a couple of layered sine waves with phase offset and amplitude from audio
        val baseAmp = h * 0.18f
        val amp = baseAmp * (0.4f + lastAmp * 0.8f)

        val freq1 = 2.0
        val freq2 = 3.0
        val samples = 120
        for (i in 0..samples) {
            val t = i.toFloat() / samples
            val x = t * w
            val y1 = centerY + amp * sin(2 * PI * (freq1 * t + phase)).toFloat()
            val y2 = centerY + (amp * 0.7f) * sin(2 * PI * (freq2 * t + phase * 0.8 + 0.25)).toFloat()
            val yg = centerY + (amp * 0.5f) * sin(2 * PI * (freq1 * 0.8 * t + phase * 1.2 + 0.1)).toFloat()
            if (i == 0) {
                path1.moveTo(x, y1)
                path2.moveTo(x, y2)
                glowPath.moveTo(x, yg)
            } else {
                path1.lineTo(x, y1)
                path2.lineTo(x, y2)
                glowPath.lineTo(x, yg)
            }
        }

        // Draw glow underlay, then waves
        canvas.drawPath(glowPath, glowPaint)
        canvas.drawPath(path2, paint2)
        canvas.drawPath(path1, paint1)
    }

    private fun dp(v: Float) = v * resources.displayMetrics.density
}
