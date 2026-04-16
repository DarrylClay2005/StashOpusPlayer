package com.stash.opusplayer.audio

import android.content.Context
import android.util.Log
import androidx.lifecycle.lifecycleScope
import com.stash.opusplayer.audio.capture.AudioDataCapture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.math.*

/**
 * Real-time Spectrum Analyzer
 * 
 * Provides real-time FFT analysis and audio visualization:
 * - FFT spectrum analysis
 * - Octave band analysis
 * - Peak detection and tracking
 * - Dynamic range measurement
 * - Frequency response analysis
 * - Audio quality metrics
 */
class SpectrumAnalyzer(private val context: Context) {
    
    private val audioDataCapture = AudioDataCapture(context)
    private val analysisScope = CoroutineScope(Dispatchers.Default + Job())
    private var analysisJob: Job? = null
    private var isEnabled = true
    
    companion object {
        private const val TAG = "SpectrumAnalyzer"
        
        // FFT settings
        const val FFT_SIZE = 2048
        const val SAMPLE_RATE = 44100
        const val FREQUENCY_BINS = FFT_SIZE / 2
        
        // Octave bands (center frequencies in Hz)
        val OCTAVE_BANDS = floatArrayOf(
            31.5f, 63f, 125f, 250f, 500f, 1000f, 2000f, 4000f, 8000f, 16000f
        )
        
        // Frequency ranges for analysis
        val BASS_RANGE = 20f to 250f
        val MID_RANGE = 250f to 4000f  
        val TREBLE_RANGE = 4000f to 20000f
    }
    
    // FFT and analysis arrays
    private val fftInput = FloatArray(FFT_SIZE)
    private val fftOutput = FloatArray(FFT_SIZE)
    private val spectrum = FloatArray(FREQUENCY_BINS)
    private val smoothedSpectrum = FloatArray(FREQUENCY_BINS)
    private val peakSpectrum = FloatArray(FREQUENCY_BINS)
    private val octaveBands = FloatArray(OCTAVE_BANDS.size)
    private var latestWaveformSamples = FloatArray(0)
    
    // Window function for FFT
    private val window = FloatArray(FFT_SIZE)
    
    // Analysis parameters
    private var smoothingFactor = 0.8f
    private var peakDecayRate = 0.95f
    private var noiseFloor = -60.0f
    
    // State flows for UI
    private val _spectrumData = MutableStateFlow(FloatArray(FREQUENCY_BINS))
    val spectrumData: StateFlow<FloatArray> = _spectrumData.asStateFlow()
    
    private val _octaveBandData = MutableStateFlow(FloatArray(OCTAVE_BANDS.size))
    val octaveBandData: StateFlow<FloatArray> = _octaveBandData.asStateFlow()
    
    private val _peakFrequency = MutableStateFlow(1000.0f)
    val peakFrequency: StateFlow<Float> = _peakFrequency.asStateFlow()
    
    private val _fundamentalFrequency = MutableStateFlow(440.0f)
    val fundamentalFrequency: StateFlow<Float> = _fundamentalFrequency.asStateFlow()
    
    private val _spectralCentroid = MutableStateFlow(2000.0f)
    val spectralCentroid: StateFlow<Float> = _spectralCentroid.asStateFlow()
    
    private val _spectralRolloff = MutableStateFlow(8000.0f)
    val spectralRolloff: StateFlow<Float> = _spectralRolloff.asStateFlow()
    
    private val _bassLevel = MutableStateFlow(-30.0f)
    val bassLevel: StateFlow<Float> = _bassLevel.asStateFlow()
    
    private val _midLevel = MutableStateFlow(-25.0f)
    val midLevel: StateFlow<Float> = _midLevel.asStateFlow()
    
    private val _trebleLevel = MutableStateFlow(-28.0f)
    val trebleLevel: StateFlow<Float> = _trebleLevel.asStateFlow()
    
    private val _totalHarmonicDistortion = MutableStateFlow(0.001f)
    val totalHarmonicDistortion: StateFlow<Float> = _totalHarmonicDistortion.asStateFlow()
    
    private val _signalToNoiseRatio = MutableStateFlow(60.0f)
    val signalToNoiseRatio: StateFlow<Float> = _signalToNoiseRatio.asStateFlow()
    
    private val _crestFactor = MutableStateFlow(6.0f)
    val crestFactor: StateFlow<Float> = _crestFactor.asStateFlow()
    
    private val _spectralFlatness = MutableStateFlow(0.5f)
    val spectralFlatness: StateFlow<Float> = _spectralFlatness.asStateFlow()
    
    init {
        initializeWindow()
    }
    
    /**
     * Initialize spectrum analyzer for audio session
     */
    fun initialize(audioSessionId: Int) {
        try {
            audioDataCapture.initialize(audioSessionId)
            startRealTimeAnalysis()
            Log.d(TAG, "SpectrumAnalyzer initialized for session $audioSessionId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize SpectrumAnalyzer", e)
        }
    }
    
    /**
     * Enable/disable spectrum analysis
     */
    fun setEnabled(enabled: Boolean) {
        isEnabled = enabled
        audioDataCapture.setEnabled(enabled)
        if (enabled) {
            startRealTimeAnalysis()
        } else {
            stopRealTimeAnalysis()
        }
    }
    
    /**
     * Release resources
     */
    fun release() {
        stopRealTimeAnalysis()
        audioDataCapture.release()
    }
    
    /**
     * Start real-time audio analysis
     */
    private fun startRealTimeAnalysis() {
        if (!isEnabled || analysisJob?.isActive == true) return
        
        analysisJob = analysisScope.launch {
            launch {
                audioDataCapture.waveformData.collect { waveform ->
                    if (waveform.isEmpty()) return@collect
                    latestWaveformSamples = waveform.map { (it.toInt() - 128) / 128.0f }.toFloatArray()
                }
            }

            audioDataCapture.fftData.collect { fftData ->
                if (isEnabled && fftData.isNotEmpty()) {
                    // Convert FFT bytes to magnitudes
                    val magnitudes = audioDataCapture.convertFftToMagnitudes(fftData)
                    
                    // Apply logarithmic scaling
                    val logMagnitudes = audioDataCapture.applyLogScaling(magnitudes)
                    
                    // Process the spectrum data
                    processSpectrumData(logMagnitudes)
                }
            }
        }
    }
    
    /**
     * Stop real-time audio analysis
     */
    private fun stopRealTimeAnalysis() {
        analysisJob?.cancel()
        analysisJob = null
    }
    
    /**
     * Process spectrum data and update analysis
     */
    private fun processSpectrumData(magnitudes: FloatArray) {
        if (magnitudes.size < FREQUENCY_BINS) return
        
        try {
            // Copy magnitudes to spectrum array
            for (i in 0 until min(magnitudes.size, FREQUENCY_BINS)) {
                spectrum[i] = magnitudes[i]
            }
            
            // Smooth the spectrum
            smoothSpectrum()
            
            // Update peak spectrum
            updatePeakSpectrum()
            
            // Calculate octave bands
            calculateOctaveBands(SAMPLE_RATE)
            
            // Perform spectral analysis
            performSpectralAnalysis(SAMPLE_RATE)
            
            // Calculate frequency band levels
            calculateFrequencyBandLevels(SAMPLE_RATE)
            
            val waveformSamples = latestWaveformSamples
            if (waveformSamples.isNotEmpty()) {
                calculateQualityMetrics(waveformSamples)
            } else {
                calculateSpectrumDrivenQualityMetrics()
            }
            
            // Update state flows
            updateStateFlows()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error processing spectrum data", e)
        }
    }
    
    private fun initializeWindow() {
        // Hann window for better frequency resolution
        for (i in 0 until FFT_SIZE) {
            window[i] = (0.5 * (1 - cos(2 * PI * i / (FFT_SIZE - 1)))).toFloat()
        }
    }
    
    /**
     * Analyze audio samples and update spectrum data
     */
    fun analyzeSamples(samples: FloatArray, sampleRate: Int = SAMPLE_RATE) {
        if (samples.size < FFT_SIZE) return
        
        try {
            // Copy and window the input
            for (i in 0 until FFT_SIZE) {
                fftInput[i] = samples[i] * window[i]
            }
            
            // Perform FFT
            performFFT(fftInput, fftOutput)
            
            // Convert to magnitude spectrum
            updateSpectrum(sampleRate)
            
            // Smooth the spectrum
            smoothSpectrum()
            
            // Update peak spectrum
            updatePeakSpectrum()
            
            // Calculate octave bands
            calculateOctaveBands(sampleRate)
            
            // Perform spectral analysis
            performSpectralAnalysis(sampleRate)
            
            // Calculate frequency band levels
            calculateFrequencyBandLevels(sampleRate)
            
            // Calculate audio quality metrics
            calculateQualityMetrics(samples)
            
            // Update state flows
            updateStateFlows()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing samples", e)
        }
    }
    
    /**
     * Simple FFT implementation using cooley-tukey algorithm
     */
    private fun performFFT(input: FloatArray, output: FloatArray) {
        val n = input.size
        if (n <= 1) return
        
        // Bit-reversal permutation
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j xor bit
            if (i < j) {
                val temp = input[i]
                input[i] = input[j]
                input[j] = temp
            }
        }
        
        // Cooley-Tukey FFT
        var length = 2
        while (length <= n) {
            val wlen = -2 * PI / length
            val wReal = cos(wlen).toFloat()
            val wImag = sin(wlen).toFloat()
            
            var i = 0
            while (i < n) {
                var wCurrentReal = 1.0f
                var wCurrentImag = 0.0f
                
                for (j in 0 until length / 2) {
                    val u = i + j
                    val v = i + j + length / 2
                    
                    val tReal = wCurrentReal * input[v]
                    val tImag = wCurrentImag * input[v]
                    
                    input[v] = input[u] - tReal
                    input[u] = input[u] + tReal
                    
                    val nextReal = wCurrentReal * wReal - wCurrentImag * wImag
                    wCurrentImag = wCurrentReal * wImag + wCurrentImag * wReal
                    wCurrentReal = nextReal
                }
                i += length
            }
            length = length shl 1
        }
        
        // Copy result
        System.arraycopy(input, 0, output, 0, n)
    }
    
    private fun updateSpectrum(sampleRate: Int) {
        for (i in 0 until FREQUENCY_BINS) {
            val real = fftOutput[i * 2]
            val imag = if (i * 2 + 1 < fftOutput.size) fftOutput[i * 2 + 1] else 0f
            val magnitude = sqrt(real * real + imag * imag)
            
            // Convert to dB
            spectrum[i] = if (magnitude > 0) {
                20 * log10(magnitude).coerceAtLeast(noiseFloor)
            } else {
                noiseFloor
            }
        }
    }
    
    private fun smoothSpectrum() {
        for (i in spectrum.indices) {
            smoothedSpectrum[i] = smoothingFactor * smoothedSpectrum[i] + 
                                 (1 - smoothingFactor) * spectrum[i]
        }
    }
    
    private fun updatePeakSpectrum() {
        for (i in spectrum.indices) {
            peakSpectrum[i] = maxOf(peakSpectrum[i] * peakDecayRate, spectrum[i])
        }
    }
    
    private fun calculateOctaveBands(sampleRate: Int) {
        val frequencyResolution = sampleRate.toFloat() / FFT_SIZE
        
        for (bandIndex in OCTAVE_BANDS.indices) {
            val centerFreq = OCTAVE_BANDS[bandIndex]
            val lowerFreq = centerFreq / sqrt(2.0).toFloat()
            val upperFreq = centerFreq * sqrt(2.0).toFloat()
            
            val lowerBin = (lowerFreq / frequencyResolution).toInt().coerceAtLeast(0)
            val upperBin = (upperFreq / frequencyResolution).toInt().coerceAtMost(FREQUENCY_BINS - 1)
            
            var bandEnergy = 0.0f
            var binCount = 0
            
            for (bin in lowerBin..upperBin) {
                val magnitude = 10.0.pow(spectrum[bin] / 20.0).toFloat()
                bandEnergy += magnitude * magnitude
                binCount++
            }
            
            octaveBands[bandIndex] = if (binCount > 0) {
                val rms = sqrt(bandEnergy / binCount)
                if (rms > 0) 20 * log10(rms) else noiseFloor
            } else {
                noiseFloor
            }
        }
    }
    
    private fun performSpectralAnalysis(sampleRate: Int) {
        val frequencyResolution = sampleRate.toFloat() / FFT_SIZE
        
        // Find peak frequency
        var maxMagnitude = Float.NEGATIVE_INFINITY
        var peakBin = 0
        
        for (i in 1 until FREQUENCY_BINS) { // Skip DC component
            if (spectrum[i] > maxMagnitude) {
                maxMagnitude = spectrum[i]
                peakBin = i
            }
        }
        
        _peakFrequency.value = peakBin * frequencyResolution
        
        // Calculate spectral centroid (brightness measure)
        var weightedSum = 0.0f
        var magnitudeSum = 0.0f
        
        for (i in 1 until FREQUENCY_BINS) {
            val magnitude = 10.0.pow(spectrum[i] / 20.0).toFloat()
            val frequency = i * frequencyResolution
            
            weightedSum += frequency * magnitude
            magnitudeSum += magnitude
        }
        
        _spectralCentroid.value = if (magnitudeSum > 0) weightedSum / magnitudeSum else 1000.0f
        
        // Calculate spectral rolloff (90% of energy cutoff)
        val totalEnergy = (1 until FREQUENCY_BINS)
            .map { 10.0.pow(spectrum[it] / 20.0).toFloat() }
            .sum()
        
        val rolloffThreshold = totalEnergy * 0.9f
        var cumulativeEnergy = 0.0f
        var rolloffBin = FREQUENCY_BINS - 1
        
        for (i in 1 until FREQUENCY_BINS) {
            cumulativeEnergy += 10.0.pow(spectrum[i] / 20.0).toFloat()
            if (cumulativeEnergy >= rolloffThreshold) {
                rolloffBin = i
                break
            }
        }
        
        _spectralRolloff.value = rolloffBin * frequencyResolution
        
        // Calculate spectral flatness (tonality measure)
        var geometricMean = 1.0
        var arithmeticMean = 0.0
        var validBins = 0
        
        for (i in 1 until FREQUENCY_BINS) {
            val magnitude = 10.0.pow(spectrum[i] / 20.0).toFloat()
            if (magnitude > 0) {
                geometricMean *= magnitude.toDouble()
                arithmeticMean += magnitude
                validBins++
            }
        }
        
        if (validBins > 0) {
            geometricMean = geometricMean.pow(1.0 / validBins)
            arithmeticMean /= validBins
            _spectralFlatness.value = if (arithmeticMean > 0) {
                (geometricMean / arithmeticMean).toFloat().coerceIn(0.0f, 1.0f)
            } else 0.0f
        }
    }
    
    private fun calculateFrequencyBandLevels(sampleRate: Int) {
        val frequencyResolution = sampleRate.toFloat() / FFT_SIZE
        
        // Bass level (20 Hz - 250 Hz)
        val bassStart = (BASS_RANGE.first / frequencyResolution).toInt().coerceAtLeast(1)
        val bassEnd = (BASS_RANGE.second / frequencyResolution).toInt().coerceAtMost(FREQUENCY_BINS - 1)
        
        val bassEnergy = (bassStart..bassEnd).map { 
            10.0.pow(spectrum[it] / 20.0).toFloat() 
        }.average().toFloat()
        
        _bassLevel.value = if (bassEnergy > 0) 20 * log10(bassEnergy) else noiseFloor
        
        // Mid level (250 Hz - 4 kHz)
        val midStart = (MID_RANGE.first / frequencyResolution).toInt().coerceAtLeast(1)
        val midEnd = (MID_RANGE.second / frequencyResolution).toInt().coerceAtMost(FREQUENCY_BINS - 1)
        
        val midEnergy = (midStart..midEnd).map { 
            10.0.pow(spectrum[it] / 20.0).toFloat() 
        }.average().toFloat()
        
        _midLevel.value = if (midEnergy > 0) 20 * log10(midEnergy) else noiseFloor
        
        // Treble level (4 kHz - 20 kHz)
        val trebleStart = (TREBLE_RANGE.first / frequencyResolution).toInt().coerceAtLeast(1)
        val trebleEnd = (TREBLE_RANGE.second / frequencyResolution).toInt().coerceAtMost(FREQUENCY_BINS - 1)
        
        val trebleEnergy = (trebleStart..trebleEnd).map { 
            10.0.pow(spectrum[it] / 20.0).toFloat() 
        }.average().toFloat()
        
        _trebleLevel.value = if (trebleEnergy > 0) 20 * log10(trebleEnergy) else noiseFloor
    }
    
    private fun calculateQualityMetrics(samples: FloatArray) {
        // Calculate crest factor (peak to RMS ratio)
        val peak = samples.maxByOrNull { abs(it) }?.let { abs(it) } ?: 0.0f
        val rms = sqrt(samples.map { it * it }.average()).toFloat()
        
        _crestFactor.value = if (rms > 0) 20 * log10(peak / rms) else 0.0f
        
        // Estimate THD (simplified)
        val fundamentalBin = (_peakFrequency.value / (SAMPLE_RATE.toFloat() / FFT_SIZE)).toInt()
        val fundamentalMagnitude = if (fundamentalBin < spectrum.size) 10.0.pow(spectrum[fundamentalBin] / 20.0).toFloat() else 0.0f
        
        var harmonicEnergy = 0.0f
        for (harmonic in 2..5) {
            val harmonicBin = fundamentalBin * harmonic
            if (harmonicBin < spectrum.size) {
                harmonicEnergy += 10.0.pow(spectrum[harmonicBin] / 20.0).toFloat()
            }
        }
        
        val thd = if (fundamentalMagnitude > 0) {
            sqrt(harmonicEnergy) / fundamentalMagnitude
        } else 0.0f
        
        _totalHarmonicDistortion.value = thd.coerceIn(0.0f, 1.0f)
        
        // Estimate SNR
        val signalEnergy = (1..100).map { 10.0.pow(spectrum[it] / 20.0).toFloat() }.average().toFloat()
        val noiseEnergy = ((FREQUENCY_BINS - 100) until FREQUENCY_BINS).map { 
            10.0.pow(spectrum[it] / 20.0).toFloat() 
        }.average().toFloat()
        
        val snr = if (noiseEnergy > 0) 20 * log10(signalEnergy / noiseEnergy) else 60.0f
        _signalToNoiseRatio.value = snr.coerceIn(0.0f, 100.0f)
    }

    private fun calculateSpectrumDrivenQualityMetrics() {
        val peakDb = spectrum.maxOrNull() ?: noiseFloor
        val averageDb = spectrum.average().toFloat().coerceAtMost(peakDb)
        _crestFactor.value = (peakDb - averageDb).coerceIn(0.0f, 24.0f)

        val fundamentalBin = (_peakFrequency.value / (SAMPLE_RATE.toFloat() / FFT_SIZE)).toInt()
        val fundamentalMagnitude = spectrum.getOrNull(fundamentalBin)
            ?.let { 10.0.pow(it / 20.0).toFloat() }
            ?: 0.0f

        var harmonicEnergy = 0.0f
        for (harmonic in 2..5) {
            val harmonicBin = fundamentalBin * harmonic
            if (harmonicBin < spectrum.size) {
                harmonicEnergy += 10.0.pow(spectrum[harmonicBin] / 20.0).toFloat()
            }
        }
        _totalHarmonicDistortion.value = if (fundamentalMagnitude > 0f) {
            (sqrt(harmonicEnergy) / fundamentalMagnitude).coerceIn(0.0f, 1.0f)
        } else {
            0.0f
        }

        val signalRange = spectrum.take(100).ifEmpty { listOf(noiseFloor) }
        val noiseRange = spectrum.takeLast(100).ifEmpty { listOf(noiseFloor) }
        val signalEnergy = signalRange.map { 10.0.pow(it / 20.0).toFloat() }.average().toFloat()
        val noiseEnergy = noiseRange.map { 10.0.pow(it / 20.0).toFloat() }.average().toFloat()
        _signalToNoiseRatio.value = if (noiseEnergy > 0f) {
            (20 * log10(signalEnergy / noiseEnergy)).coerceIn(0.0f, 100.0f)
        } else {
            60.0f
        }
    }
    
    private fun updateStateFlows() {
        _spectrumData.value = smoothedSpectrum.copyOf()
        _octaveBandData.value = octaveBands.copyOf()
    }
    
    // Configuration methods
    fun setSmoothingFactor(factor: Float) {
        smoothingFactor = factor.coerceIn(0.0f, 1.0f)
    }
    
    fun setPeakDecayRate(rate: Float) {
        peakDecayRate = rate.coerceIn(0.0f, 1.0f)
    }
    
    fun setNoiseFloor(floor: Float) {
        noiseFloor = floor.coerceIn(-120.0f, 0.0f)
    }
    
    // Utility functions
    fun getFrequencyForBin(bin: Int, sampleRate: Int = SAMPLE_RATE): Float {
        return bin * sampleRate.toFloat() / FFT_SIZE
    }
    
    fun getBinForFrequency(frequency: Float, sampleRate: Int = SAMPLE_RATE): Int {
        return (frequency * FFT_SIZE / sampleRate).toInt().coerceIn(0, FREQUENCY_BINS - 1)
    }
    
    fun getSpectrumAtFrequency(frequency: Float, sampleRate: Int = SAMPLE_RATE): Float {
        val bin = getBinForFrequency(frequency, sampleRate)
        return if (bin < spectrum.size) spectrum[bin] else noiseFloor
    }
    
    fun reset() {
        smoothedSpectrum.fill(noiseFloor)
        peakSpectrum.fill(noiseFloor)
        octaveBands.fill(noiseFloor)
    }
}
