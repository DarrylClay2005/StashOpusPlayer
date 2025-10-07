package com.stash.opusplayer.utils

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import java.net.*
import java.util.*

/**
 * Utility class for network-related operations including IP address detection
 */
object NetworkUtils {
    
    private const val TAG = "NetworkUtils"
    
    /**
     * Auto-detect the local IP address of the device
     * Tries multiple methods to find the most suitable IP
     */
    fun getLocalIpAddress(context: Context? = null): String {
        // Try WiFi first if context is available
        context?.let { ctx ->
            val wifiIp = getWifiIpAddress(ctx)
            if (wifiIp.isNotEmpty() && isValidLocalIp(wifiIp)) {
                Log.d(TAG, "Using WiFi IP: $wifiIp")
                return wifiIp
            }
        }
        
        // Try network interfaces
        val networkIp = getNetworkInterfaceIp()
        if (networkIp.isNotEmpty() && isValidLocalIp(networkIp)) {
            Log.d(TAG, "Using network interface IP: $networkIp")
            return networkIp
        }
        
        // Try socket method as fallback
        val socketIp = getIpBySocket()
        if (socketIp.isNotEmpty() && isValidLocalIp(socketIp)) {
            Log.d(TAG, "Using socket-detected IP: $socketIp")
            return socketIp
        }
        
        // Final fallback
        Log.w(TAG, "Could not detect local IP, using localhost")
        return "127.0.0.1"
    }
    
    /**
     * Get IP address from WiFi connection
     */
    private fun getWifiIpAddress(context: Context): String {
        return try {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val wifiInfo = wifiManager.connectionInfo
            val ipInt = wifiInfo.ipAddress
            
            if (ipInt == 0) return ""
            
            String.format(
                Locale.getDefault(),
                "%d.%d.%d.%d",
                (ipInt and 0xff),
                (ipInt shr 8 and 0xff),
                (ipInt shr 16 and 0xff),
                (ipInt shr 24 and 0xff)
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error getting WiFi IP: ${e.message}")
            ""
        }
    }
    
    /**
     * Get IP address from network interfaces
     */
    private fun getNetworkInterfaceIp(): String {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            for (networkInterface in Collections.list(interfaces)) {
                // Skip loopback and inactive interfaces
                if (networkInterface.isLoopback || !networkInterface.isUp) continue
                
                val addresses = networkInterface.inetAddresses
                for (address in Collections.list(addresses)) {
                    if (!address.isLoopbackAddress && address is Inet4Address) {
                        val ip = address.hostAddress
                        if (ip != null && isValidLocalIp(ip)) {
                            return ip
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting network interface IP: ${e.message}")
        }
        return ""
    }
    
    /**
     * Get IP address by connecting to a socket
     */
    private fun getIpBySocket(): String {
        return try {
            Socket().use { socket ->
                // Connect to Google's public DNS to determine local IP
                socket.connect(InetSocketAddress("8.8.8.8", 80))
                socket.localAddress.hostAddress ?: ""
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting IP by socket: ${e.message}")
            ""
        }
    }
    
    /**
     * Check if the IP address is a valid local/private IP
     */
    private fun isValidLocalIp(ip: String): Boolean {
        if (ip.isEmpty() || ip == "127.0.0.1") return false
        
        return try {
            val parts = ip.split(".")
            if (parts.size != 4) return false
            
            val first = parts[0].toInt()
            val second = parts[1].toInt()
            
            // Check for private IP ranges
            when (first) {
                10 -> true // 10.0.0.0/8
                172 -> second in 16..31 // 172.16.0.0/12
                192 -> second == 168 // 192.168.0.0/16
                else -> false
            }
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Test if a service is reachable at the given IP and port
     */
    fun isServiceReachable(ip: String, port: Int, timeoutMs: Int = 5000): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(ip, port), timeoutMs)
                true
            }
        } catch (e: Exception) {
            Log.d(TAG, "Service not reachable at $ip:$port - ${e.message}")
            false
        }
    }
    
    /**
     * Find available download services by scanning common ports
     */
    fun findAvailableDownloadServices(baseIp: String? = null): List<ServiceInfo> {
        val targetIp = baseIp ?: getLocalIpAddress()
        val services = mutableListOf<ServiceInfo>()
        val ports = listOf(8082, 8083, 8080, 8081, 3000, 5000)
        
        Log.d(TAG, "Scanning for download services on IP: $targetIp")
        
        for (port in ports) {
            if (isServiceReachable(targetIp, port, 2000)) {
                // Try to determine service type by checking endpoints
                val serviceType = detectServiceType(targetIp, port)
                services.add(ServiceInfo(targetIp, port, serviceType))
                Log.d(TAG, "Found service at $targetIp:$port - Type: $serviceType")
            }
        }
        
        return services
    }
    
    /**
     * Detect the type of service running on a given IP and port
     */
    private fun detectServiceType(ip: String, port: Int): ServiceType {
        return try {
            val url = "http://$ip:$port"
            
            // Check for health endpoint (our multi-platform service)
            if (isEndpointAvailable("$url/health")) {
                ServiceType.MULTI_PLATFORM
            }
            // Check for quick endpoint (YouTube downloader)
            else if (isEndpointAvailable("$url/quick")) {
                ServiceType.YOUTUBE_DOWNLOADER
            }
            // Check for platforms endpoint
            else if (isEndpointAvailable("$url/platforms")) {
                ServiceType.MULTI_PLATFORM
            }
            else {
                ServiceType.UNKNOWN
            }
        } catch (e: Exception) {
            ServiceType.UNKNOWN
        }
    }
    
    /**
     * Check if a specific endpoint is available
     */
    private fun isEndpointAvailable(url: String): Boolean {
        return try {
            val connection = URL(url).openConnection()
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            connection.connect()
            true
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * Data class to hold service information
     */
    data class ServiceInfo(
        val ip: String,
        val port: Int,
        val type: ServiceType
    ) {
        val baseUrl: String get() = "http://$ip:$port"
        val quickUrl: String get() = "$baseUrl/quick"
    }
    
    /**
     * Enum for different service types
     */
    enum class ServiceType {
        MULTI_PLATFORM,
        YOUTUBE_DOWNLOADER,
        UNKNOWN
    }
}