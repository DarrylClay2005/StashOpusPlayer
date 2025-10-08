package com.stash.opusplayer.audio.capture

import android.content.Context
import android.media.audiofx.Visualizer
import android.util.Log
import androidx.media3.common.C
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Captures real-time audio data from the audio session for spectrum analysis
 */
class AudioDataCapture(private val context: Context) {
    
    companion object {
        private const val TAG = "AudioDataCapture"
        private const val CAPTURE_SIZE = 1024
    }
    
    private var visualizer: Visualizer? = null
    private var isEnabled = false
    
    // Audio data streams
    private val _waveformData = MutableStateFlow(ByteArray(CAPTURE_SIZE))
    val waveformData: StateFlow<ByteArray> = _waveformData.asStateFlow()
    
    private val _fftData = MutableStateFlow(ByteArray(CAPTURE_SIZE))
    val fftData: StateFlow<ByteArray> = _fftData.asStateFlow()
    
    private val _samplingRate = MutableStateFlow(44100)
    val samplingRate: StateFlow<Int> = _samplingRate.asStateFlow()
    
    fun initialize(audioSessionId: Int) {
        try {
            release()
            
            if (audioSessionId == C.AUDIO_SESSION_ID_UNSET) {
                Log.w(TAG, "Cannot initialize with invalid audio session ID")
                return
            }
            
            visualizer = Visualizer(audioSessionId).apply {
                captureSize = CAPTURE_SIZE
                
                setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?,
                        waveform: ByteArray?,
                        samplingRate: Int
                    ) {
                        waveform?.let { 
                            _waveformData.value = it.copyOf()
                            _samplingRate.value = samplingRate
                        }
                    }
                    
                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        fft: ByteArray?,
                        samplingRate: Int
                    ) {
                        fft?.let { 
                            _fftData.value = it.copyOf()
                            _samplingRate.value = samplingRate
                        }
                    }
                }, Visualizer.getMaxCaptureRate() / 2, true, true)
                
                enabled = isEnabled
            }
            
            Log.d(TAG, "AudioDataCapture initialized for session $audioSessionId")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize AudioDataCapture", e)
            visualizer = null
        }
    }
    
    fun setEnabled(enabled: Boolean) {
        isEnabled = enabled
        try {
            visualizer?.enabled = enabled
            Log.d(TAG, "AudioDataCapture enabled: $enabled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set AudioDataCapture enabled state", e)
        }
    }
    
    fun release() {
        try {
            visualizer?.release()
            visualizer = null
            Log.d(TAG, "AudioDataCapture released")
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing AudioDataCapture", e)
        }
    }
    
    /**
     * Convert raw FFT bytes to magnitude spectrum
     */
    fun convertFftToMagnitudes(fftBytes: ByteArray): FloatArray {
        val magnitudes = FloatArray(fftBytes.size / 2)
        
        // DC component
        magnitudes[0] = kotlin.math.abs(fftBytes[0].toFloat())
        
        // Process the rest of the FFT data
        for (i in 1 until magnitudes.size) {
            val realIndex = i * 2
            val imagIndex = realIndex + 1
            
            if (imagIndex < fftBytes.size) {
                val real = fftBytes[realIndex].toFloat()
                val imag = fftBytes[imagIndex].toFloat()
                magnitudes[i] = kotlin.math.sqrt(real * real + imag * imag)
            }
        }
        
        return magnitudes
    }
    
    /**
     * Apply logarithmic scaling to magnitudes for better visualization
     */
    fun applyLogScaling(magnitudes: FloatArray): FloatArray {
        return magnitudes.map { magnitude ->
            if (magnitude > 0f) {
                20f * kotlin.math.log10(magnitude + 1f)
            } else {
                0f
            }
        }.toFloatArray()
    }
    
    /**
     * Get frequency for a given FFT bin
     */
    fun getFrequencyForBin(binIndex: Int, fftSize: Int, samplingRate: Int): Float {
        return (binIndex.toFloat() * samplingRate) / fftSize
    }
}