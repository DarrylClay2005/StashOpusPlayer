package com.stash.opusplayer.data

import com.google.gson.annotations.SerializedName
import java.util.Date

data class GitHubRelease(
    @SerializedName("tag_name")
    val tagName: String,
    
    @SerializedName("name")
    val name: String,
    
    @SerializedName("body")
    val body: String,
    
    @SerializedName("published_at")
    val publishedAt: String,
    
    @SerializedName("prerelease")
    val prerelease: Boolean,
    
    @SerializedName("draft")
    val draft: Boolean,
    
    @SerializedName("assets")
    val assets: List<GitHubAsset>,
    
    @SerializedName("html_url")
    val htmlUrl: String
) {
    val versionName: String
        get() = tagName.removePrefix("v")
    
    val versionCode: Int
        get() {
            return try {
                val parts = versionName.split(".")
                when (parts.size) {
                    2 -> parts[0].toInt() * 10 + parts[1].toInt()
                    3 -> parts[0].toInt() * 100 + parts[1].toInt() * 10 + parts[2].toInt()
                    else -> 0
                }
            } catch (e: Exception) {
                0
            }
        }
    
    val releaseApk: GitHubAsset?
        get() = assets.find { 
            it.name.contains("release") && it.name.endsWith(".apk") 
        }
    
    val debugApk: GitHubAsset?
        get() = assets.find { 
            it.name.contains("debug") && it.name.endsWith(".apk") 
        }
    
    fun isNewerThan(currentVersion: String): Boolean {
        return try {
            val currentCode = parseVersionCode(currentVersion)
            versionCode > currentCode
        } catch (e: Exception) {
            false
        }
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
}

data class GitHubAsset(
    @SerializedName("name")
    val name: String,
    
    @SerializedName("size")
    val size: Long,
    
    @SerializedName("download_count")
    val downloadCount: Int,
    
    @SerializedName("browser_download_url")
    val downloadUrl: String,
    
    @SerializedName("content_type")
    val contentType: String
) {
    val fileSizeMB: String
        get() = "%.1f MB".format(size / (1024.0 * 1024.0))
}
