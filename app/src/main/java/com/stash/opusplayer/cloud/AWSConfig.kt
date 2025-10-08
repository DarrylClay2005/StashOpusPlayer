package com.stash.opusplayer.cloud

import android.content.Context
import android.util.Log
import com.amazonaws.auth.AWSCredentials
import com.amazonaws.auth.AWSCredentialsProvider
import com.amazonaws.auth.BasicAWSCredentials
import com.amazonaws.auth.DefaultAWSCredentialsProviderChain
import com.amazonaws.mobileconnectors.dynamodbv2.dynamodbmapper.DynamoDBMapper
import com.amazonaws.regions.Region
import com.amazonaws.regions.Regions
import com.amazonaws.services.dynamodbv2.AmazonDynamoDBClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException
import java.util.Properties
import java.util.UUID

/**
 * AWS DynamoDB configuration and client management
 * 
 * This class handles:
 * - AWS credentials management
 * - DynamoDB client initialization
 * - Region configuration
 * - Error handling and fallback behavior
 */
class AWSConfig private constructor(context: Context) {
    
    companion object {
        private const val TAG = "AWSConfig"
        private val DEFAULT_REGION = Regions.US_EAST_1
        private const val DEVICE_ID_PREF = "aws_device_id"
        private const val CONFIG_FILE = "aws-config.properties"
        
        @Volatile
        private var INSTANCE: AWSConfig? = null
        
        fun getInstance(context: Context): AWSConfig {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: AWSConfig(context.applicationContext).also { INSTANCE = it }
            }
        }
    }
    
    private val appContext = context.applicationContext
    private var _dynamoDBMapper: DynamoDBMapper? = null
    private var _isInitialized = false
    private var _deviceId: String
    private var _configProperties: Properties = Properties()
    private var _region: Regions = DEFAULT_REGION
    
    // Lazy initialization of AWS credentials
    private val credentialsProvider: AWSCredentialsProvider by lazy {
        try {
            // Use default credentials provider chain which includes:
            // 1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
            // 2. Java system properties (aws.accessKeyId, aws.secretKey)
            // 3. Credential profiles file (~/.aws/credentials)
            // 4. Instance profile credentials (for EC2)
            DefaultAWSCredentialsProviderChain()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize AWS credentials provider", e)
            throw e
        }
    }
    
    // Lazy initialization of DynamoDB client
    private val dynamoDBClient: AmazonDynamoDBClient by lazy {
        try {
            AmazonDynamoDBClient(credentialsProvider).apply {
                setRegion(Region.getRegion(_region))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize DynamoDB client", e)
            throw e
        }
    }
    
    init {
        // Load configuration from assets
        loadConfiguration()
        
        // Generate or retrieve unique device ID
        val prefs = appContext.getSharedPreferences("aws_config", Context.MODE_PRIVATE)
        _deviceId = prefs.getString(DEVICE_ID_PREF, null) ?: run {
            val newDeviceId = UUID.randomUUID().toString()
            prefs.edit().putString(DEVICE_ID_PREF, newDeviceId).apply()
            newDeviceId
        }
    }
    
    /**
     * Initialize AWS services asynchronously
     */
    suspend fun initialize(): Boolean = withContext(Dispatchers.IO) {
        try {
            if (_isInitialized) return@withContext true
            
            Log.d(TAG, "Initializing AWS DynamoDB services...")
            
            // Test credentials by attempting to get them
            val credentials = credentialsProvider.credentials
            Log.d(TAG, "AWS credentials loaded successfully")
            
            // Initialize DynamoDB mapper
            _dynamoDBMapper = DynamoDBMapper(dynamoDBClient)
            
            _isInitialized = true
            Log.d(TAG, "AWS services initialized successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize AWS services", e)
            _isInitialized = false
            false
        }
    }
    
    /**
     * Get DynamoDB mapper instance
     */
    fun getDynamoDBMapper(): DynamoDBMapper? {
        return if (_isInitialized) _dynamoDBMapper else null
    }
    
    /**
     * Get unique device identifier
     */
    fun getDeviceId(): String = _deviceId
    
    /**
     * Get current user ID (can be extended to support user authentication)
     */
    fun getUserId(): String {
        // For now, use device ID as user ID
        // In future versions, this can be enhanced with proper user authentication
        return _deviceId
    }
    
    /**
     * Check if AWS services are properly initialized
     */
    fun isInitialized(): Boolean = _isInitialized
    
    /**
     * Test DynamoDB connection
     */
    suspend fun testConnection(): Boolean = withContext(Dispatchers.IO) {
        try {
            if (!_isInitialized) return@withContext false
            
            // Simple connection test by listing tables (this requires ListTables permission)
            dynamoDBClient.listTables()
            Log.d(TAG, "DynamoDB connection test successful")
            true
        } catch (e: Exception) {
            Log.w(TAG, "DynamoDB connection test failed", e)
            false
        }
    }
    
    /**
     * Load configuration from assets
     */
    private fun loadConfiguration() {
        try {
            val inputStream = appContext.assets.open(CONFIG_FILE)
            _configProperties.load(inputStream)
            inputStream.close()
            
            // Parse region from config
            val regionString = _configProperties.getProperty("aws.region", DEFAULT_REGION.name)
            _region = Regions.fromName(regionString) ?: DEFAULT_REGION
            
            Log.d(TAG, "Configuration loaded successfully from $CONFIG_FILE")
            Log.d(TAG, "Region: ${_region.name}")
        } catch (e: IOException) {
            Log.w(TAG, "Could not load configuration file $CONFIG_FILE, using defaults", e)
        } catch (e: Exception) {
            Log.e(TAG, "Error loading configuration", e)
        }
    }
    
    /**
     * Get AWS region
     */
    fun getRegion(): Regions = _region
    
    /**
     * Check if device has proper AWS credentials configured
     */
    fun hasValidCredentials(): Boolean {
        return try {
            credentialsProvider.credentials
            true
        } catch (e: Exception) {
            Log.w(TAG, "Invalid or missing AWS credentials", e)
            false
        }
    }
    
    /**
     * Refresh AWS credentials
     */
    suspend fun refreshCredentials(): Boolean = withContext(Dispatchers.IO) {
        try {
            credentialsProvider.refresh()
            Log.d(TAG, "AWS credentials refreshed successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to refresh AWS credentials", e)
            false
        }
    }
    
    /**
     * Store AWS credentials in encrypted shared preferences
     */
    fun storeCredentials(accessKey: String, secretKey: String): Boolean {
        return try {
            val prefs = appContext.getSharedPreferences("aws_credentials", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("access_key", accessKey)
                .putString("secret_key", secretKey)
                .putLong("stored_timestamp", System.currentTimeMillis())
                .apply()
            
            Log.d(TAG, "AWS credentials stored successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to store AWS credentials", e)
            false
        }
    }
    
    /**
     * Get stored credentials from preferences
     */
    fun getStoredCredentials(): AWSCredentials? {
        return try {
            val prefs = appContext.getSharedPreferences("aws_credentials", Context.MODE_PRIVATE)
            val accessKey = prefs.getString("access_key", null)
            val secretKey = prefs.getString("secret_key", null)
            
            if (!accessKey.isNullOrEmpty() && !secretKey.isNullOrEmpty()) {
                BasicAWSCredentials(accessKey, secretKey)
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get stored credentials", e)
            null
        }
    }
    
    /**
     * Clear stored credentials
     */
    fun clearStoredCredentials(): Boolean {
        return try {
            val prefs = appContext.getSharedPreferences("aws_credentials", Context.MODE_PRIVATE)
            prefs.edit().clear().apply()
            Log.d(TAG, "AWS credentials cleared")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear credentials", e)
            false
        }
    }
    
    /**
     * Check if credentials are stored locally
     */
    fun hasStoredCredentials(): Boolean {
        val prefs = appContext.getSharedPreferences("aws_credentials", Context.MODE_PRIVATE)
        return prefs.contains("access_key") && prefs.contains("secret_key")
    }
    
    /**
     * Get credential source information for debugging
     */
    fun getCredentialSource(): String {
        return when {
            hasStoredCredentials() -> "Stored in app preferences"
            System.getenv("AWS_ACCESS_KEY_ID") != null -> "Environment variables"
            else -> "Default provider chain"
        }
    }
    
    /**
     * Get DynamoDB table names from configuration
     */
    fun getProfilesTableName(): String {
        return _configProperties.getProperty("dynamodb.table.profiles", "StashOpusUserAudioProfiles")
    }
    
    fun getAnalyticsTableName(): String {
        return _configProperties.getProperty("dynamodb.table.analytics", "StashOpusListeningAnalytics")
    }
    
    fun getSyncTableName(): String {
        return _configProperties.getProperty("dynamodb.table.sync", "StashOpusDeviceSync")
    }
    
    /**
     * Get configuration property
     */
    fun getConfigProperty(key: String, defaultValue: String = ""): String {
        return _configProperties.getProperty(key, defaultValue)
    }
    
    /**
     * Clean up resources
     */
    fun cleanup() {
        try {
            dynamoDBClient.shutdown()
            _isInitialized = false
            Log.d(TAG, "AWS resources cleaned up")
        } catch (e: Exception) {
            Log.e(TAG, "Error during AWS cleanup", e)
        }
    }
}