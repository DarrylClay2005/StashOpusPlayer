package com.stash.opusplayer.ui.views

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import com.stash.opusplayer.R
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

class SpectrumView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private const val FFT_SIZE = 1024
        private const val SPECTRUM_BANDS = 128
        private const val MIN_DB = -60f
        private const val MAX_DB = 0f
        private const val SMOOTHING_FACTOR = 0.7f
        private const val BAR_SPACING = 2f
        private const val PEAK_HOLD_TIME = 30 // frames
    }

    // Paint objects for rendering
    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    
    private val peakPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = ContextCompat.getColor(context, R.color.accent_color)
    }
    
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f
        color = ContextCompat.getColor(context, R.color.text_secondary)
        alpha = 64
    }
    
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = 24f
        color = ContextCompat.getColor(context, R.color.text_secondary)
    }

    // Gradient for spectrum bars
    private var barGradient: LinearGradient? = null
    
    // Spectrum data
    private var magnitudes = FloatArray(SPECTRUM_BANDS) { MIN_DB }
    private var smoothedMagnitudes = FloatArray(SPECTRUM_BANDS) { MIN_DB }
    private var peakMagnitudes = FloatArray(SPECTRUM_BANDS) { MIN_DB }
    private var peakHoldCounters = IntArray(SPECTRUM_BANDS) { 0 }
    
    // Frequency labels
    private val frequencyLabels = arrayOf("60", "250", "1K", "4K", "16K")
    private val frequencyPositions = FloatArray(frequencyLabels.size)
    
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        
        // Create gradient for spectrum bars
        barGradient = LinearGradient(
            0f, height.toFloat(),
            0f, 0f,
            intArrayOf(
                ContextCompat.getColor(context, R.color.spectrum_low),
                ContextCompat.getColor(context, R.color.spectrum_mid),
                ContextCompat.getColor(context, R.color.spectrum_high)
            ),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        )
        
        barPaint.shader = barGradient
        
        // Calculate frequency label positions
        calculateFrequencyPositions()
    }
    
    private fun calculateFrequencyPositions() {
        val totalWidth = width.toFloat()
        val barWidth = (totalWidth - BAR_SPACING * (SPECTRUM_BANDS - 1)) / SPECTRUM_BANDS
        
        // Map frequency labels to positions (logarithmic scale)
        val frequencies = floatArrayOf(60f, 250f, 1000f, 4000f, 16000f)
        val nyquist = 22050f // Assuming 44.1kHz sample rate
        
        for (i in frequencies.indices) {
            val normalizedFreq = frequencies[i] / nyquist
            val position = normalizedFreq * totalWidth
            frequencyPositions[i] = min(position, totalWidth - 100f) // Ensure labels fit
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        
        val width = width.toFloat()
        val height = height.toFloat()
        
        if (width <= 0 || height <= 0) return
        
        // Draw background grid
        drawGrid(canvas, width, height)
        
        // Draw spectrum bars
        drawSpectrum(canvas, width, height)
        
        // Draw frequency labels
        drawFrequencyLabels(canvas, height)
    }
    
    private fun drawGrid(canvas: Canvas, width: Float, height: Float) {
        // Horizontal grid lines (dB levels)
        val dbStep = 10f
        val dbRange = MAX_DB - MIN_DB
        val stepHeight = height / (dbRange / dbStep)
        
        var currentDb = MAX_DB
        var y = 0f
        
        while (currentDb >= MIN_DB) {
            canvas.drawLine(0f, y, width, y, gridPaint)
            currentDb -= dbStep
            y += stepHeight
        }
        
        // Vertical grid lines (frequency markers)
        for (position in frequencyPositions) {
            canvas.drawLine(position, 0f, position, height, gridPaint)
        }
    }
    
    private fun drawSpectrum(canvas: Canvas, width: Float, height: Float) {
        val barWidth = (width - BAR_SPACING * (SPECTRUM_BANDS - 1)) / SPECTRUM_BANDS
        var x = 0f
        
        for (i in 0 until SPECTRUM_BANDS) {
            val magnitude = smoothedMagnitudes[i]
            val peakMagnitude = peakMagnitudes[i]
            
            // Calculate bar height (in dB scale)
            val normalizedMagnitude = (magnitude - MIN_DB) / (MAX_DB - MIN_DB)
            val barHeight = normalizedMagnitude * height
            
            // Calculate peak height
            val normalizedPeak = (peakMagnitude - MIN_DB) / (MAX_DB - MIN_DB)
            val peakY = height - (normalizedPeak * height)
            
            // Draw spectrum bar
            if (barHeight > 0) {
                canvas.drawRect(
                    x, height - barHeight,
                    x + barWidth, height,
                    barPaint
                )
            }
            
            // Draw peak indicator
            if (peakMagnitude > MIN_DB) {
                canvas.drawRect(
                    x, peakY - 2f,
                    x + barWidth, peakY,
                    peakPaint
                )
            }
            
            x += barWidth + BAR_SPACING
        }
    }
    
    private fun drawFrequencyLabels(canvas: Canvas, height: Float) {
        for (i in frequencyLabels.indices) {
            val x = frequencyPositions[i]
            val label = frequencyLabels[i]
            
            // Measure text to center it
            val textBounds = Rect()
            labelPaint.getTextBounds(label, 0, label.length, textBounds)
            val textWidth = textBounds.width()
            
            canvas.drawText(
                label,
                x - textWidth / 2f,
                height - 8f,
                labelPaint
            )
        }
    }
    
    /**
     * Update spectrum data from FFT magnitudes
     */
    fun updateSpectrum(fftMagnitudes: FloatArray) {
        if (fftMagnitudes.size < FFT_SIZE / 2) return
        
        // Convert FFT magnitudes to dB and map to spectrum bands
        val nyquist = 22050f // Assuming 44.1kHz sample rate
        val freqStep = nyquist / (FFT_SIZE / 2)
        
        for (i in 0 until SPECTRUM_BANDS) {
            // Logarithmic frequency mapping
            val startFreq = 20f * (1000.0.pow(i.toDouble() / SPECTRUM_BANDS)).toFloat()
            val endFreq = 20f * (1000.0.pow((i + 1).toDouble() / SPECTRUM_BANDS)).toFloat()
            
            val startBin = (startFreq / freqStep).toInt().coerceIn(0, fftMagnitudes.size - 1)
            val endBin = (endFreq / freqStep).toInt().coerceIn(startBin, fftMagnitudes.size - 1)
            
            // Average magnitude in frequency band
            var sum = 0f
            var count = 0
            
            for (bin in startBin..endBin) {
                if (bin < fftMagnitudes.size) {
                    sum += fftMagnitudes[bin]
                    count++
                }
            }
            
            val avgMagnitude = if (count > 0) sum / count else 0f
            
            // Convert to dB
            val dbValue = if (avgMagnitude > 0f) {
                20f * log10(avgMagnitude).coerceIn(MIN_DB, MAX_DB)
            } else {
                MIN_DB
            }
            
            magnitudes[i] = dbValue
        }
        
        // Apply smoothing
        for (i in 0 until SPECTRUM_BANDS) {
            smoothedMagnitudes[i] = smoothedMagnitudes[i] * SMOOTHING_FACTOR +
                    magnitudes[i] * (1f - SMOOTHING_FACTOR)
            
            // Update peaks with hold
            if (smoothedMagnitudes[i] > peakMagnitudes[i]) {
                peakMagnitudes[i] = smoothedMagnitudes[i]
                peakHoldCounters[i] = PEAK_HOLD_TIME
            } else {
                peakHoldCounters[i]--
                if (peakHoldCounters[i] <= 0) {
                    peakMagnitudes[i] = max(peakMagnitudes[i] - 0.5f, smoothedMagnitudes[i])
                }
            }
        }
        
        // Trigger redraw
        invalidate()
    }
    
    /**
     * Reset spectrum display
     */
    fun reset() {
        magnitudes.fill(MIN_DB)
        smoothedMagnitudes.fill(MIN_DB)
        peakMagnitudes.fill(MIN_DB)
        peakHoldCounters.fill(0)
        invalidate()
    }
    
    /**
     * Set spectrum sensitivity
     */
    fun setSensitivity(sensitivity: Float) {
        // Adjust minimum dB based on sensitivity
        val adjustedMinDb = MIN_DB + (sensitivity - 1f) * 20f
        // Update display accordingly
        invalidate()
    }
}