package com.stash.opusplayer.audio.utils

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.system.measureTimeMillis

/**
 * Performance optimization utilities for enhanced audio processing
 */
object AudioPerformanceOptimizer {
    
    private const val TAG = "AudioPerformanceOptimizer"
    
    // Performance monitoring
    private var processingTimes = mutableListOf<Long>()
    private var maxProcessingTime = 0L
    private var averageProcessingTime = 0.0
    
    /**
     * Measure processing time for audio operations
     */
    inline fun <T> measureProcessingTime(operation: String, block: () -> T): T {
        val result: T
        val time = measureTimeMillis {
            result = block()
        }
        
        recordProcessingTime(operation, time)
        return result
    }
    
    /**
     * Record processing time for monitoring
     */
    fun recordProcessingTime(operation: String, timeMs: Long) {
        processingTimes.add(timeMs)
        
        // Keep only last 100 measurements
        if (processingTimes.size > 100) {
            processingTimes.removeAt(0)
        }
        
        // Update statistics
        maxProcessingTime = maxOf(maxProcessingTime, timeMs)
        averageProcessingTime = processingTimes.average()
        
        // Log warning if processing time is high
        if (timeMs > 10) { // More than 10ms is concerning for real-time audio
            Log.w(TAG, "High processing time for $operation: ${timeMs}ms")
        }
        
        // Log debug info periodically
        if (processingTimes.size % 50 == 0) {
            Log.d(TAG, "Audio processing stats - Avg: ${averageProcessingTime.toInt()}ms, Max: ${maxProcessingTime}ms")
        }
    }
    
    /**
     * Optimize array operations for better performance
     */
    fun optimizeArrayCopy(source: FloatArray, destination: FloatArray, size: Int = source.size) {
        try {
            System.arraycopy(source, 0, destination, 0, minOf(size, source.size, destination.size))
        } catch (e: Exception) {
            // Fallback to manual copy
            val copySize = minOf(size, source.size, destination.size)
            for (i in 0 until copySize) {
                destination[i] = source[i]
            }
        }
    }
    
    /**
     * Efficient FFT magnitude calculation
     */
    fun calculateMagnitudes(fftReal: FloatArray, fftImag: FloatArray, output: FloatArray) {
        val size = minOf(fftReal.size, fftImag.size, output.size)
        
        for (i in 0 until size) {
            val real = fftReal[i]
            val imag = fftImag[i]
            output[i] = kotlin.math.sqrt(real * real + imag * imag)
        }
    }
    
    /**
     * Fast approximate logarithm for spectrum scaling
     */
    fun fastLog10(x: Float): Float {
        if (x <= 0f) return -60f // Minimum dB value
        
        // Fast approximation using bit manipulation
        val bits = java.lang.Float.floatToIntBits(x)
        val exp = ((bits shr 23) and 0xFF) - 127
        val mantissa = (bits and 0x7FFFFF) or 0x3F800000
        val mantissaFloat = java.lang.Float.intBitsToFloat(mantissa)
        
        // Polynomial approximation for log10
        val logMantissa = -1.49278f + (2.11263f - 0.729104f * mantissaFloat) * mantissaFloat
        return 0.301029996f * (exp + logMantissa)
    }
    
    /**
     * Memory-efficient spectrum smoothing
     */
    fun smoothSpectrum(current: FloatArray, previous: FloatArray, smoothing: Float, output: FloatArray) {
        val size = minOf(current.size, previous.size, output.size)
        val oneMinusSmoothing = 1f - smoothing
        
        for (i in 0 until size) {
            output[i] = smoothing * previous[i] + oneMinusSmoothing * current[i]
        }
    }
    
    /**
     * Batch processing for multiple audio effects
     */
    suspend fun <T> batchProcess(
        items: List<T>,
        batchSize: Int = 32,
        processor: suspend (List<T>) -> Unit
    ) = withContext(Dispatchers.Default) {
        items.chunked(batchSize).forEach { batch ->
            processor(batch)
        }
    }
    
    /**
     * Memory pool for frequent allocations
     */
    object MemoryPool {
        internal val floatArrays = mutableMapOf<Int, MutableList<FloatArray>>()
        private val maxPoolSize = 10
        
        fun getFloatArray(size: Int): FloatArray {
            val pool = floatArrays.getOrPut(size) { mutableListOf() }
            return if (pool.isNotEmpty()) {
                pool.removeAt(pool.lastIndex)
            } else {
                FloatArray(size)
            }
        }
        
        fun returnFloatArray(array: FloatArray) {
            val size = array.size
            val pool = floatArrays.getOrPut(size) { mutableListOf() }
            
            if (pool.size < maxPoolSize) {
                // Clear the array before returning to pool
                array.fill(0f)
                pool.add(array)
            }
        }
        
        fun clearPools() {
            floatArrays.clear()
        }
    }
    
    /**
     * Get current performance statistics
     */
    fun getPerformanceStats(): Map<String, Any> {
        return mapOf(
            "averageProcessingTime" to averageProcessingTime,
            "maxProcessingTime" to maxProcessingTime,
            "totalMeasurements" to processingTimes.size,
            "memoryPoolSizes" to getPoolSizes()
        )
    }
    
    /**
     * Get memory pool sizes
     */
    private fun getPoolSizes(): Map<Int, Int> {
        return MemoryPool.floatArrays.mapValues { it.value.size }
    }
    
    /**
     * Reset performance statistics
     */
    fun resetStats() {
        processingTimes.clear()
        maxProcessingTime = 0L
        averageProcessingTime = 0.0
        MemoryPool.clearPools()
    }
}