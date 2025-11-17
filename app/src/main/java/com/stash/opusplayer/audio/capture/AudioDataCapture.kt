package com.stash.opusplayer.audio.capture

import android.content.Context
import android.media.audiofx.Visualizer
import android.util.Log
import androidx.media3.common.C
import com.stash.opusplayer.utils.PermissionHelper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.sin
import kotlin.random.Random

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
    private var useMockData = false
    private var mockDataCounter = 0
    
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
                Log.w(TAG, "Cannot initialize with invalid audio session ID, using mock data")
                useMockData = true
                startMockDataGeneration()
                return
            }
            
            // Check permission first
            if (!PermissionHelper.hasRecordAudioPermission(context)) {
                Log.w(TAG, "RECORD_AUDIO permission not granted, using mock data")
                useMockData = true
                startMockDataGeneration()
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
                }, Visualizer.getMaxCaptureRate() / 10, true, false)  // Reduced from /2 to /10, only capture FFT
                
                enabled = isEnabled
            }
            
            useMockData = false
            Log.d(TAG, "AudioDataCapture initialized successfully for session $audioSessionId")
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize AudioDataCapture: ${e.message}", e)
            when {
                e.message?.contains("error: -3") == true -> 
                    Log.e(TAG, "AudioFlinger error - likely missing RECORD_AUDIO permission or audio session conflict")
                else -> 
                    Log.e(TAG, "Unknown visualizer initialization error")
            }
            // Fall back to mock data
            visualizer = null
            useMockData = true
            startMockDataGeneration()
        }
    }
    
    fun setEnabled(enabled: Boolean) {
        isEnabled = enabled
        
        if (useMockData && enabled) {
            // Generate mock data periodically
            _waveformData.value = generateMockWaveform()
            _fftData.value = generateMockFft()
            Log.d(TAG, "AudioDataCapture (mock mode) enabled: $enabled")
            return
        }
        
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
    
    /**
     * Check if running in mock mode
     */
    fun isMockMode(): Boolean = useMockData
    
    /**
     * Start generating mock data for visualizations
     */
    private fun startMockDataGeneration() {
        Log.i(TAG, "Starting mock data generation for visualizers")
        // Mock data will be generated on demand in getter methods
    }
    
    /**
     * Generate mock waveform data with smooth sine wave pattern
     */
    private fun generateMockWaveform(): ByteArray {
        mockDataCounter++
        return ByteArray(CAPTURE_SIZE) { i ->
            val phase = (mockDataCounter * 0.1f + i * 0.05f)
            (128 + 64 * sin(phase)).toInt().toByte()
        }
    }
    
    /**
     * Generate mock FFT data with realistic frequency distribution
     */
    private fun generateMockFft(): ByteArray {
        return ByteArray(CAPTURE_SIZE) { i ->
            when {
                i < 100 -> (Random.nextFloat() * 180 + 40).toInt().toByte() // Bass
                i < 300 -> (Random.nextFloat() * 120 + 20).toInt().toByte() // Mids
                else -> (Random.nextFloat() * 60 + 10).toInt().toByte() // Highs
            }
        }
    }
}
