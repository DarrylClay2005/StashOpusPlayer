package com.stash.opusplayer.data

import android.os.Parcelable
import kotlinx.parcelize.Parcelize
import java.text.SimpleDateFormat
import java.util.*

@Parcelize
data class UpdateInfo(
    val currentVersion: String,
    val latestVersion: String,
    val versionName: String,
    val releaseNotes: String,
    val downloadUrl: String,
    val fileSize: String,
    val publishedDate: String,
    val isForced: Boolean = false,
    val isCritical: Boolean = false
) : Parcelable {
    
    val isUpdateAvailable: Boolean
        get() = latestVersion != currentVersion && parseVersionCode(latestVersion) > parseVersionCode(currentVersion)
    
    val formattedReleaseNotes: String
        get() = releaseNotes.take(500) + if (releaseNotes.length > 500) "..." else ""
    
    val updatePriority: UpdatePriority
        get() = when {
            isForced -> UpdatePriority.CRITICAL
            isCritical -> UpdatePriority.HIGH
            majorVersionDifference() -> UpdatePriority.MEDIUM
            else -> UpdatePriority.LOW
        }
    
    private fun parseVersionCode(version: String): Int {
        return try {
            val parts = version.split(".")
            when (parts.size) {
                2 -> parts[0].toInt() * 10 + parts[1].toInt()
                3 -> parts[0].toInt() * 100 + parts[1].toInt() * 10 + parts[2].toInt()
                else -> 0
            }
        } catch (e: Exception) {
            0
        }
    }
    
    private fun majorVersionDifference(): Boolean {
        return try {
            val currentMajor = currentVersion.split(".")[0].toInt()
            val latestMajor = latestVersion.split(".")[0].toInt()
            latestMajor > currentMajor
        } catch (e: Exception) {
            false
        }
    }
    
    val formattedPublishedDate: String
        get() = try {
            val inputFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.getDefault())
            val outputFormat = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault())
            val date = inputFormat.parse(publishedDate)
            outputFormat.format(date ?: Date())
        } catch (e: Exception) {
            publishedDate
        }
}

enum class UpdatePriority(val displayName: String, val color: Int) {
    LOW("Optional Update", 0xFF4CAF50.toInt()),
    MEDIUM("Recommended Update", 0xFFFF9800.toInt()),
    HIGH("Important Update", 0xFFFF5722.toInt()),
    CRITICAL("Critical Update", 0xFFF44336.toInt())
}
