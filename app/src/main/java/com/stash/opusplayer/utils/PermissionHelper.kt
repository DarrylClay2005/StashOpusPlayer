package com.stash.opusplayer.utils

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/**
 * Permission Helper Utility
 * Manages runtime permission requests for RECORD_AUDIO permission
 * required by Android Visualizer API
 */
object PermissionHelper {
    const val RECORD_AUDIO_PERMISSION_CODE = 1001
    
    /**
     * Check if RECORD_AUDIO permission is granted
     */
    fun hasRecordAudioPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Permission granted by default on API < 23
        }
    }
    
    /**
     * Request RECORD_AUDIO permission from user
     */
    fun requestRecordAudioPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                RECORD_AUDIO_PERMISSION_CODE
            )
        }
    }
    
    /**
     * Check if we should show permission rationale to user
     */
    fun shouldShowRationale(activity: Activity): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ActivityCompat.shouldShowRequestPermissionRationale(
                activity,
                Manifest.permission.RECORD_AUDIO
            )
        } else {
            false
        }
    }
}
