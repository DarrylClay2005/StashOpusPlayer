package com.stash.opusplayer.audio.service

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * TEMPORARY STUB - Basic functionality only
 */
class RevolutionaryAudioService : Service() {
    
    companion object {
        const val REVOLUTIONARY_CHANNEL_ID = "revolutionary_channel"
        const val ADVANCED_CHANNEL_ID = "advanced_channel"
        const val ACTION_REVOLUTIONARY_STOP = "action_stop"
        const val ACTION_REVOLUTIONARY_PLAY = "action_play"
        const val ACTION_REVOLUTIONARY_PAUSE = "action_pause"
        const val ACTION_REVOLUTIONARY_NEXT = "action_next"
        const val ACTION_REVOLUTIONARY_PREVIOUS = "action_previous"
        const val ACTION_TOGGLE_AI_MODE = "action_toggle_ai"
        const val ACTION_ADJUST_BASS = "action_adjust_bass"
        const val ACTION_ADJUST_SPATIAL = "action_adjust_spatial"
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onCreate() {
        super.onCreate()
        // Basic service setup
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Handle basic commands
        return START_STICKY
    }
    
    override fun onDestroy() {
        super.onDestroy()
    }
}