package com.stash.opusplayer.updates

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import com.stash.opusplayer.R
import com.stash.opusplayer.data.UpdateInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit

class UpdateDownloader(private val context: Context) {
    
    private val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
    
    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "update_downloads"
        private const val DOWNLOAD_NOTIFICATION_ID = 1001
        private const val INSTALL_NOTIFICATION_ID = 1002
    }
    
    init {
        createNotificationChannel()
    }
    
    suspend fun downloadUpdate(
        updateInfo: UpdateInfo,
        onProgress: (Int) -> Unit = {},
        onComplete: (File) -> Unit = {},
        onError: (String) -> Unit = {}
    ) = withContext(Dispatchers.IO) {
        try {
            // Create downloads directory
            val downloadsDir = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "updates")
            if (!downloadsDir.exists()) {
                downloadsDir.mkdirs()
            }
            
            // Create file name
            val fileName = "stash_opus_player_v${updateInfo.latestVersion}.apk"
            val updateFile = File(downloadsDir, fileName)
            
            // Delete existing file if it exists
            if (updateFile.exists()) {
                updateFile.delete()
            }
            
            // Show download notification
            showDownloadNotification(updateInfo)
            
            // Download the file
            val request = Request.Builder()
                .url(updateInfo.downloadUrl)
                .addHeader("User-Agent", "StashOpusPlayer-UpdateDownloader/2.0")
                .build()
            
            okHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    withContext(Dispatchers.Main) {
                        onError("Download failed: ${response.message}")
                    }
                    return@withContext
                }
                
                val body = response.body ?: throw IOException("Empty response body")
                val contentLength = body.contentLength()
                
                FileOutputStream(updateFile).use { fileOut ->
                    body.byteStream().use { inputStream ->
                        val buffer = ByteArray(8192)
                        var downloadedBytes = 0L
                        var bytesRead: Int
                        
                        while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                            fileOut.write(buffer, 0, bytesRead)
                            downloadedBytes += bytesRead
                            
                            if (contentLength > 0) {
                                val progress = ((downloadedBytes * 100) / contentLength).toInt()
                                withContext(Dispatchers.Main) {
                                    onProgress(progress)
                                }
                                updateDownloadNotification(updateInfo, progress)
                            }
                        }
                    }
                }
            }
            
            // Download complete
            notificationManager.cancel(DOWNLOAD_NOTIFICATION_ID)
            showInstallNotification(updateInfo, updateFile)
            
            withContext(Dispatchers.Main) {
                onComplete(updateFile)
            }
            
        } catch (e: Exception) {
            notificationManager.cancel(DOWNLOAD_NOTIFICATION_ID)
            withContext(Dispatchers.Main) {
                onError("Download failed: ${e.message}")
            }
        }
    }
    
    fun installUpdate(updateFile: File) {
        try {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    updateFile
                )
            } else {
                Uri.fromFile(updateFile)
            }
            
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            }
            
            context.startActivity(intent)
            
        } catch (e: Exception) {
            // Fallback: Show file location to user
            showInstallInstructions(updateFile)
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Update Downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notifications for app update downloads"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun showDownloadNotification(updateInfo: UpdateInfo) {
        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_system_update)
            .setContentTitle("Downloading Update")
            .setContentText("Stash Opus Player v${updateInfo.latestVersion}")
            .setProgress(100, 0, false)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        
        notificationManager.notify(DOWNLOAD_NOTIFICATION_ID, notification)
    }
    
    private fun updateDownloadNotification(updateInfo: UpdateInfo, progress: Int) {
        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_system_update)
            .setContentTitle("Downloading Update")
            .setContentText("Stash Opus Player v${updateInfo.latestVersion} - $progress%")
            .setProgress(100, progress, false)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        
        notificationManager.notify(DOWNLOAD_NOTIFICATION_ID, notification)
    }
    
    private fun showInstallNotification(updateInfo: UpdateInfo, updateFile: File) {
        val installIntent = createInstallIntent(updateFile)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            installIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_system_update)
            .setContentTitle("Update Ready to Install")
            .setContentText("Tap to install Stash Opus Player v${updateInfo.latestVersion}")
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .addAction(
                R.drawable.ic_system_update,
                "Install Now",
                pendingIntent
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        
        notificationManager.notify(INSTALL_NOTIFICATION_ID, notification)
    }
    
    private fun createInstallIntent(updateFile: File): Intent {
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                updateFile
            )
        } else {
            Uri.fromFile(updateFile)
        }
        
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
    }
    
    private fun showInstallInstructions(updateFile: File) {
        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_info)
            .setContentTitle("Manual Installation Required")
            .setContentText("Open file: ${updateFile.name}")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("The update has been downloaded to:\n${updateFile.absolutePath}\n\nPlease open this file to install the update."))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        
        notificationManager.notify(INSTALL_NOTIFICATION_ID, notification)
    }
}
