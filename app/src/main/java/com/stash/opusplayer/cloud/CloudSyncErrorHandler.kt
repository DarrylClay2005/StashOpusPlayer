package com.stash.opusplayer.cloud

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import com.amazonaws.AmazonServiceException
import com.amazonaws.AmazonClientException
import kotlinx.coroutines.*
import java.net.UnknownHostException
import java.net.SocketTimeoutException
import java.util.concurrent.TimeoutException

/**
 * Centralized error handling for cloud sync operations
 */
class CloudSyncErrorHandler(private val context: Context) {
    
    companion object {
        private const val TAG = "CloudSyncErrorHandler"
        
        // Retry configuration
        private const val MAX_RETRIES = 3
        private const val BASE_DELAY_MS = 1000L
        private const val MAX_DELAY_MS = 10000L
        
        // Error categories
        enum class ErrorCategory {
            NETWORK,
            AUTHENTICATION,
            PERMISSION,
            SERVICE_UNAVAILABLE,
            DATA_CONFLICT,
            UNKNOWN
        }
        
        data class CloudSyncError(
            val category: ErrorCategory,
            val message: String,
            val isRetryable: Boolean,
            val userMessage: String,
            val originalException: Exception?
        )
    }
    
    /**
     * Execute operation with comprehensive error handling and retry logic
     */
    suspend fun <T> executeWithRetry(
        operation: suspend () -> T,
        maxRetries: Int = MAX_RETRIES,
        delayMs: Long = BASE_DELAY_MS
    ): Result<T> {
        var lastError: Exception? = null
        
        repeat(maxRetries + 1) { attempt ->
            try {
                // Check network connectivity before each attempt
                if (!isNetworkAvailable()) {
                    throw NetworkUnavailableException("Network not available")
                }
                
                val result = withTimeout(30000) { // 30 second timeout
                    operation()
                }
                return Result.success(result)
                
            } catch (e: Exception) {
                lastError = e
                val error = categorizeError(e)
                
                Log.w(TAG, "Operation failed (attempt ${attempt + 1}): ${error.message}", e)
                
                // Don't retry if it's not retryable or this is the last attempt
                if (!error.isRetryable || attempt >= maxRetries) {
                    return Result.failure(e)
                }
                
                // Calculate delay with exponential backoff
                val delay = minOf(delayMs * (1L shl attempt), MAX_DELAY_MS)
                Log.d(TAG, "Retrying in ${delay}ms...")
                delay(delay)
            }
        }
        
        return Result.failure(lastError ?: Exception("Unknown error"))
    }
    
    /**
     * Categorize exceptions into error types
     */
    fun categorizeError(exception: Exception): CloudSyncError {
        return when (exception) {
            is NetworkUnavailableException -> CloudSyncError(
                ErrorCategory.NETWORK,
                "Network not available",
                true,
                "No internet connection. Please check your network and try again.",
                exception
            )
            
            is UnknownHostException -> CloudSyncError(
                ErrorCategory.NETWORK,
                "Unable to resolve AWS endpoint",
                true,
                "Cannot connect to cloud services. Please check your internet connection.",
                exception
            )
            
            is SocketTimeoutException, is TimeoutException -> CloudSyncError(
                ErrorCategory.NETWORK,
                "Network timeout",
                true,
                "Connection timed out. Please try again.",
                exception
            )
            
            is AmazonServiceException -> {
                when (exception.statusCode) {
                    401, 403 -> CloudSyncError(
                        ErrorCategory.AUTHENTICATION,
                        "AWS authentication failed: ${exception.message}",
                        false,
                        "Authentication failed. Please check your AWS credentials.",
                        exception
                    )
                    
                    404 -> CloudSyncError(
                        ErrorCategory.SERVICE_UNAVAILABLE,
                        "AWS resource not found: ${exception.message}",
                        false,
                        "Cloud service configuration error. Please contact support.",
                        exception
                    )
                    
                    409 -> CloudSyncError(
                        ErrorCategory.DATA_CONFLICT,
                        "Data conflict: ${exception.message}",
                        true,
                        "Data sync conflict detected. Attempting to resolve...",
                        exception
                    )
                    
                    429 -> CloudSyncError(
                        ErrorCategory.SERVICE_UNAVAILABLE,
                        "Rate limit exceeded: ${exception.message}",
                        true,
                        "Too many requests. Please wait a moment and try again.",
                        exception
                    )
                    
                    500, 502, 503 -> CloudSyncError(
                        ErrorCategory.SERVICE_UNAVAILABLE,
                        "AWS service error: ${exception.message}",
                        true,
                        "Cloud service temporarily unavailable. Please try again later.",
                        exception
                    )
                    
                    else -> CloudSyncError(
                        ErrorCategory.UNKNOWN,
                        "AWS service error: ${exception.message}",
                        true,
                        "An error occurred with cloud services. Please try again.",
                        exception
                    )
                }
            }
            
            is AmazonClientException -> CloudSyncError(
                ErrorCategory.NETWORK,
                "AWS client error: ${exception.message}",
                true,
                "Connection to cloud services failed. Please check your internet connection.",
                exception
            )
            
            is SecurityException -> CloudSyncError(
                ErrorCategory.PERMISSION,
                "Security exception: ${exception.message}",
                false,
                "Permission error. Please check app permissions.",
                exception
            )
            
            else -> CloudSyncError(
                ErrorCategory.UNKNOWN,
                exception.message ?: "Unknown error",
                true,
                "An unexpected error occurred. Please try again.",
                exception
            )
        }
    }
    
    /**
     * Check if network is available
     */
    private fun isNetworkAvailable(): Boolean {
        return try {
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            
            val network = connectivityManager.activeNetwork ?: return false
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
            
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking network availability", e)
            false
        }
    }
    
    /**
     * Handle specific sync conflict scenarios
     */
    suspend fun handleDataConflict(
        localData: Any,
        remoteData: Any,
        conflictResolver: suspend (local: Any, remote: Any) -> Any
    ): Any {
        return try {
            Log.d(TAG, "Resolving data conflict...")
            val resolvedData = conflictResolver(localData, remoteData)
            Log.d(TAG, "Data conflict resolved successfully")
            resolvedData
        } catch (e: Exception) {
            Log.e(TAG, "Failed to resolve data conflict", e)
            throw e
        }
    }
    
    /**
     * Log sync operation metrics for monitoring
     */
    fun logSyncMetrics(
        operation: String,
        success: Boolean,
        durationMs: Long,
        retryCount: Int = 0,
        error: CloudSyncError? = null
    ) {
        val status = if (success) "SUCCESS" else "FAILURE"
        Log.i(TAG, "SYNC_METRICS: operation=$operation, status=$status, duration=${durationMs}ms, retries=$retryCount")
        
        if (!success && error != null) {
            Log.w(TAG, "SYNC_ERROR: operation=$operation, category=${error.category}, message=${error.message}")
        }
    }
    
    /**
     * Create user-friendly error message
     */
    fun createUserMessage(error: CloudSyncError, context: String = ""): String {
        val prefix = if (context.isNotEmpty()) "[$context] " else ""
        return "$prefix${error.userMessage}"
    }
    
    /**
     * Check if error should trigger a credential refresh
     */
    fun shouldRefreshCredentials(error: CloudSyncError): Boolean {
        return error.category == ErrorCategory.AUTHENTICATION
    }
    
    /**
     * Check if error should disable auto-sync temporarily
     */
    fun shouldDisableAutoSync(error: CloudSyncError): Boolean {
        return error.category == ErrorCategory.AUTHENTICATION ||
               error.category == ErrorCategory.PERMISSION ||
               (!error.isRetryable && error.category == ErrorCategory.SERVICE_UNAVAILABLE)
    }
}

/**
 * Custom exception for network unavailable
 */
class NetworkUnavailableException(message: String) : Exception(message)

/**
 * Custom exception for sync conflicts
 */
class SyncConflictException(
    message: String,
    val localData: Any,
    val remoteData: Any
) : Exception(message)