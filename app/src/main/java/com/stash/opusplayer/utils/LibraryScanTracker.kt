package com.stash.opusplayer.utils

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import android.util.Log

object LibraryScanTracker {
    private val _status = MutableStateFlow("")
    val status: StateFlow<String> = _status
    
    private var scanInProgress = false

    fun startScan(message: String) {
        if (scanInProgress) {
            Log.w("LibraryScanTracker", "Scan already in progress, ignoring: $message")
            return
        }
        scanInProgress = true
        _status.value = message
        Log.d("LibraryScanTracker", "Started scan: $message")
    }
    
    fun update(message: String) {
        if (!scanInProgress) {
            Log.w("LibraryScanTracker", "No scan in progress, starting: $message")
            startScan(message)
            return
        }
        _status.value = message
        Log.d("LibraryScanTracker", "Updated scan: $message")
    }
    
    fun completeScan() {
        scanInProgress = false
        _status.value = ""
        Log.d("LibraryScanTracker", "Completed scan")
    }
    
    fun isScanInProgress(): Boolean = scanInProgress
}
