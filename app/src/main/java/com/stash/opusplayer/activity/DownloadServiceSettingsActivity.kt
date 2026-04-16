package com.stash.opusplayer.activity

import android.os.Bundle
import android.util.Log
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.R
import com.stash.opusplayer.service.ExtractionServiceConfig
import com.stash.opusplayer.service.CustomYouTubeExtractionService
import com.stash.opusplayer.utils.NetworkUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Settings activity for managing download service configuration
 * Includes auto-detection, service discovery, and manual configuration options
 */
class DownloadServiceSettingsActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "DownloadServiceSettings"
    }

    private lateinit var autoDetectSwitch: Switch
    private lateinit var currentServiceText: TextView
    private lateinit var detectedIpText: TextView
    private lateinit var serviceStatusText: TextView
    private lateinit var scanServicesButton: Button
    private lateinit var testConnectivityButton: Button
    private lateinit var servicesRecyclerView: RecyclerView
    private lateinit var platformsRecyclerView: RecyclerView
    private lateinit var refreshButton: Button
    
    private lateinit var customYouTubeService: CustomYouTubeExtractionService
    private lateinit var servicesAdapter: ServiceAdapter
    private lateinit var platformsAdapter: PlatformAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_download_service_settings)
        
        initViews()
        initServices()
        setupListeners()
        updateDisplayedInfo()
    }

    private fun initViews() {
        autoDetectSwitch = findViewById(R.id.autoDetectSwitch)
        currentServiceText = findViewById(R.id.currentServiceText)
        detectedIpText = findViewById(R.id.detectedIpText)
        serviceStatusText = findViewById(R.id.serviceStatusText)
        scanServicesButton = findViewById(R.id.scanServicesButton)
        testConnectivityButton = findViewById(R.id.testConnectivityButton)
        servicesRecyclerView = findViewById(R.id.servicesRecyclerView)
        platformsRecyclerView = findViewById(R.id.platformsRecyclerView)
        refreshButton = findViewById(R.id.refreshButton)
        
        // Setup RecyclerViews
        servicesAdapter = ServiceAdapter { serviceInfo ->
            onServiceSelected(serviceInfo)
        }
        servicesRecyclerView.layoutManager = LinearLayoutManager(this)
        servicesRecyclerView.adapter = servicesAdapter
        
        platformsAdapter = PlatformAdapter()
        platformsRecyclerView.layoutManager = LinearLayoutManager(this)
        platformsRecyclerView.adapter = platformsAdapter
        
        autoDetectSwitch.isChecked = ExtractionServiceConfig.isAutoDetectEnabled(this)
    }

    private fun initServices() {
        customYouTubeService = CustomYouTubeExtractionService(this)
    }

    private fun setupListeners() {
        autoDetectSwitch.setOnCheckedChangeListener { _, isChecked ->
            ExtractionServiceConfig.setAutoDetectEnabled(this, isChecked)
            Toast.makeText(
                this,
                if (isChecked) "Auto-detect enabled" else "Auto-detect disabled",
                Toast.LENGTH_SHORT
            ).show()
            updateDisplayedInfo()
        }

        scanServicesButton.setOnClickListener {
            scanForServices()
        }

        testConnectivityButton.setOnClickListener {
            testServiceConnectivity()
        }
        
        refreshButton.setOnClickListener {
            updateDisplayedInfo()
            scanForServices()
            loadSupportedPlatforms()
        }
    }

    private fun updateDisplayedInfo() {
        lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                // Get current IP
                val detectedIp = NetworkUtils.getLocalIpAddress(this@DownloadServiceSettingsActivity)
                
                // Get current service URL
                val currentService = ExtractionServiceConfig.getServiceUrl(this@DownloadServiceSettingsActivity)
                
                withContext(Dispatchers.Main) {
                    detectedIpText.text = "Detected IP: $detectedIp"
                    currentServiceText.text = "Current Service: $currentService"
                    
                    // Update status
                    serviceStatusText.text = "Status: Checking..."
                    serviceStatusText.setTextColor(
                        androidx.core.content.ContextCompat.getColor(
                            this@DownloadServiceSettingsActivity,
                            android.R.color.holo_orange_dark
                        )
                    )
                }
            }
            
            // Test connectivity
            testServiceConnectivity()
        }
    }

    private fun scanForServices() {
        lifecycleScope.launch {
            scanServicesButton.isEnabled = false
            scanServicesButton.text = "Scanning..."
            
            try {
                val services = withContext(Dispatchers.IO) {
                    ExtractionServiceConfig.discoverServices(this@DownloadServiceSettingsActivity)
                }
                
                servicesAdapter.updateServices(services)
                
                Toast.makeText(this@DownloadServiceSettingsActivity, 
                    "Found ${services.size} services", Toast.LENGTH_SHORT).show()
                    
            } catch (e: Exception) {
                Log.e(TAG, "Service scan failed", e)
                Toast.makeText(this@DownloadServiceSettingsActivity,
                    "Service scan failed: ${e.message}", Toast.LENGTH_LONG).show()
            }
            
            scanServicesButton.isEnabled = true
            scanServicesButton.text = "Scan for Services"
        }
    }

    private fun testServiceConnectivity() {
        lifecycleScope.launch {
            testConnectivityButton.isEnabled = false
            testConnectivityButton.text = "Testing..."
            
            try {
                val isHealthy = withContext(Dispatchers.IO) {
                    ExtractionServiceConfig.testServiceConnectivity(this@DownloadServiceSettingsActivity)
                }
                
                if (isHealthy) {
                    serviceStatusText.text = "Status: ✅ Healthy"
                    serviceStatusText.setTextColor(
                        androidx.core.content.ContextCompat.getColor(
                            this@DownloadServiceSettingsActivity,
                            android.R.color.holo_green_dark
                        )
                    )
                } else {
                    serviceStatusText.text = "Status: ❌ Unreachable"
                    serviceStatusText.setTextColor(
                        androidx.core.content.ContextCompat.getColor(
                            this@DownloadServiceSettingsActivity,
                            android.R.color.holo_red_dark
                        )
                    )
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "Connectivity test failed", e)
                serviceStatusText.text = "Status: ❌ Error"
                serviceStatusText.setTextColor(
                    androidx.core.content.ContextCompat.getColor(
                        this@DownloadServiceSettingsActivity,
                        android.R.color.holo_red_dark
                    )
                )
            }
            
            testConnectivityButton.isEnabled = true
            testConnectivityButton.text = "Test Connectivity"
        }
    }

    private fun loadSupportedPlatforms() {
        lifecycleScope.launch {
            try {
                val result = customYouTubeService.getSupportedPlatforms()
                
                if (result.isSuccess) {
                    val platformsJson = result.getOrNull()
                    val platformsList = mutableListOf<PlatformInfo>()
                    
                    platformsJson?.getJSONArray("platforms")?.let { platforms ->
                        for (i in 0 until platforms.length()) {
                            val platform = platforms.getJSONObject(i)
                            platformsList.add(
                                PlatformInfo(
                                    name = platform.getString("name"),
                                    domain = platform.getString("domain"),
                                    status = platform.getString("status")
                                )
                            )
                        }
                    }
                    
                    platformsAdapter.updatePlatforms(platformsList)
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load platforms", e)
            }
        }
    }

    private fun onServiceSelected(serviceInfo: NetworkUtils.ServiceInfo) {
        // Show confirmation dialog
        android.app.AlertDialog.Builder(this)
            .setTitle("Switch Service")
            .setMessage("Switch to service at ${serviceInfo.baseUrl}?\n\nType: ${serviceInfo.type}")
            .setPositiveButton("Switch") { _, _ ->
                ExtractionServiceConfig.setSelectedServiceUrl(this, serviceInfo.quickUrl)
                Toast.makeText(this, "Switched to ${serviceInfo.quickUrl}", Toast.LENGTH_LONG).show()
                updateDisplayedInfo()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    override fun onResume() {
        super.onResume()
        loadSupportedPlatforms()
    }

    // Adapter for services list
    private class ServiceAdapter(
        private val onServiceClick: (NetworkUtils.ServiceInfo) -> Unit
    ) : RecyclerView.Adapter<ServiceAdapter.ServiceViewHolder>() {
        
        private var services = listOf<NetworkUtils.ServiceInfo>()
        
        fun updateServices(newServices: List<NetworkUtils.ServiceInfo>) {
            services = newServices
            notifyDataSetChanged()
        }
        
        override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): ServiceViewHolder {
            val view = android.view.LayoutInflater.from(parent.context)
                .inflate(android.R.layout.simple_list_item_2, parent, false)
            return ServiceViewHolder(view)
        }
        
        override fun onBindViewHolder(holder: ServiceViewHolder, position: Int) {
            holder.bind(services[position], onServiceClick)
        }
        
        override fun getItemCount() = services.size
        
        class ServiceViewHolder(itemView: android.view.View) : RecyclerView.ViewHolder(itemView) {
            private val titleText: TextView = itemView.findViewById(android.R.id.text1)
            private val subtitleText: TextView = itemView.findViewById(android.R.id.text2)
            
            fun bind(service: NetworkUtils.ServiceInfo, onClick: (NetworkUtils.ServiceInfo) -> Unit) {
                titleText.text = "${service.ip}:${service.port}"
                subtitleText.text = "Type: ${service.type}"
                
                itemView.setOnClickListener {
                    onClick(service)
                }
            }
        }
    }

    // Adapter for platforms list
    private class PlatformAdapter : RecyclerView.Adapter<PlatformAdapter.PlatformViewHolder>() {
        
        private var platforms = listOf<PlatformInfo>()
        
        fun updatePlatforms(newPlatforms: List<PlatformInfo>) {
            platforms = newPlatforms
            notifyDataSetChanged()
        }
        
        override fun onCreateViewHolder(parent: android.view.ViewGroup, viewType: Int): PlatformViewHolder {
            val view = android.view.LayoutInflater.from(parent.context)
                .inflate(android.R.layout.simple_list_item_2, parent, false)
            return PlatformViewHolder(view)
        }
        
        override fun onBindViewHolder(holder: PlatformViewHolder, position: Int) {
            holder.bind(platforms[position])
        }
        
        override fun getItemCount() = platforms.size
        
        class PlatformViewHolder(itemView: android.view.View) : RecyclerView.ViewHolder(itemView) {
            private val titleText: TextView = itemView.findViewById(android.R.id.text1)
            private val subtitleText: TextView = itemView.findViewById(android.R.id.text2)
            
            fun bind(platform: PlatformInfo) {
                titleText.text = platform.name
                subtitleText.text = "${platform.domain} - ${platform.status}"
                
                // Color code by status
                val color = when (platform.status.lowercase()) {
                    "active" -> android.graphics.Color.GREEN
                    "limited" -> android.graphics.Color.YELLOW
                    "blocked" -> android.graphics.Color.RED
                    else -> android.graphics.Color.GRAY
                }
                
                subtitleText.setTextColor(color)
            }
        }
    }

    // Data class for platform information
    data class PlatformInfo(
        val name: String,
        val domain: String,
        val status: String
    )
}
