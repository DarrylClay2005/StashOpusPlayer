package com.stash.opusplayer.ui.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import androidx.core.content.ContextCompat
import com.stash.opusplayer.R
import java.security.MessageDigest
import kotlin.math.max
import kotlin.math.min

class WaveformProgressView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val filledPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.accent_color)
        style = Paint.Style.FILL
    }
    private val emptyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x33FFFFFF
        style = Paint.Style.FILL
    }

    private var amplitudes: FloatArray = generateAmplitudes("default")
    private var progress: Float = 0f // 0..1

    private var barCount = 80
    private var barWidthPx = 6f
    private var barGapPx = 4f
    private var maxBarHeightRatio = 0.66f

    private var onSeek: ((ratio: Float) -> Unit)? = null

    fun setOnSeekListener(listener: ((Float) -> Unit)?) {
        onSeek = listener
    }

    fun setSeed(seed: String) {
        amplitudes = generateAmplitudes(seed)
        invalidate()
    }

    fun setProgress(currentMs: Long, durationMs: Long) {
        if (durationMs > 0) {
            progress = min(1f, max(0f, currentMs.toFloat() / durationMs.toFloat()))
            invalidate()
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        // recompute bar count based on width
        val w = MeasureSpec.getSize(widthMeasureSpec).toFloat()
        if (w > 0f) {
            val totalPerBar = barWidthPx + barGapPx
            barCount = max(20, (w / totalPerBar).toInt())
            if (amplitudes.size != barCount) {
                // stretch amplitudes to new count
                val newArr = FloatArray(barCount) { i ->
                    val idx = i * amplitudes.size / barCount
                    amplitudes[min(idx, amplitudes.lastIndex)]
                }
                amplitudes = newArr
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return
        val maxBarH = h * maxBarHeightRatio
        val startY = (h - maxBarH) / 2f
        var x = 0f
        val per = barWidthPx + barGapPx
        val filledBars = (progress * barCount).toInt()
        for (i in 0 until barCount) {
            val amp = amplitudes[i]
            val barH = max(2f, maxBarH * amp)
            val top = startY + (maxBarH - barH)
            val paint = if (i <= filledBars) filledPaint else emptyPaint
            canvas.drawRoundRect(x, top, x + barWidthPx, top + barH, 3f, 3f, paint)
            x += per
            if (x > w) break
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP -> {
                val ratio = min(1f, max(0f, event.x / width.toFloat()))
                progress = ratio
                invalidate()
                if (event.action == MotionEvent.ACTION_UP) {
                    onSeek?.invoke(ratio)
                }
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    private fun generateAmplitudes(seed: String): FloatArray {
        val md = MessageDigest.getInstance("SHA-1")
        val hash = md.digest(seed.toByteArray())
        val arr = FloatArray(barCount)
        for (i in 0 until barCount) {
            val b = hash[i % hash.size].toInt() and 0xFF
            // Create smoother distribution 0.2..1.0 with a curve
            val v = 0.2f + (b / 255f)
            arr[i] = (v * v).coerceIn(0.2f, 1.0f)
        }
        return arr
    }
}
